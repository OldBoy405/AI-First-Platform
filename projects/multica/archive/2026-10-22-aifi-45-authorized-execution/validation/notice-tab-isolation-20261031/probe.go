//go:build windows

// Command probe proves the effective sandbox, rather than trusting its name.
package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"net"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"syscall"
	"time"
	"unsafe"
)

const (
	tokenCapabilities    = 30
	tokenAppContainerSid = 31
)

var minimalEnvironmentKeys = []string{
	"APPDATA", "CGO_ENABLED", "GOARCH", "GOCACHE", "GOENV", "GOFLAGS",
	"GOOS", "GOPATH", "GOPROXY", "GOSUMDB", "GOTELEMETRY", "GOTOOLCHAIN",
	"GOWORK", "HOME", "LOCALAPPDATA", "PATH", "SystemRoot", "TEMP", "TMP",
	"USERPROFILE", "WINDIR",
}

type probeReport struct {
	Schema                 string   `json:"schema"`
	AppContainerSIDMatched bool     `json:"appContainerSidMatched"`
	NetworkCapabilitySIDs  []string `json:"networkCapabilitySids"`
	EnvironmentExact       bool     `json:"environmentExact"`
	EnvironmentKeys        []string `json:"environmentKeys"`
	OwnFileRoundTrip       bool     `json:"ownFileRoundTrip"`
	SentinelReadDenied     bool     `json:"sentinelReadDenied"`
	SentinelWriteDenied    bool     `json:"sentinelWriteDenied"`
	LoopbackRefused        bool     `json:"loopbackRefused"`
	LoopbackError          string   `json:"loopbackError"`
	Failure                string   `json:"failure,omitempty"`
}

func environmentExact() (bool, []string) {
	allowed := make(map[string]bool, len(minimalEnvironmentKeys))
	for _, key := range minimalEnvironmentKeys {
		allowed[strings.ToUpper(key)] = true
	}
	seen := make(map[string]bool)
	var keys []string
	for _, entry := range os.Environ() {
		key, _, ok := strings.Cut(entry, "=")
		if !ok || !allowed[strings.ToUpper(key)] || seen[strings.ToUpper(key)] {
			return false, keys
		}
		seen[strings.ToUpper(key)] = true
		keys = append(keys, key)
	}
	for _, key := range minimalEnvironmentKeys {
		if !seen[strings.ToUpper(key)] {
			return false, keys
		}
	}
	sort.Strings(keys)
	return true, keys
}

func queryToken(token syscall.Token, class int) ([]byte, error) {
	var needed uint32
	_ = syscall.GetTokenInformation(token, uint32(class), nil, 0, &needed)
	if needed == 0 || needed > 1<<20 {
		return nil, fmt.Errorf("invalid token information size %d for class %d", needed, class)
	}
	buffer := make([]byte, needed)
	if err := syscall.GetTokenInformation(token, uint32(class), &buffer[0], needed, &needed); err != nil {
		return nil, err
	}
	return buffer, nil
}

func sidText(sid uintptr) (string, error) {
	convert := syscall.NewLazyDLL("advapi32.dll").NewProc("ConvertSidToStringSidW")
	localFree := syscall.NewLazyDLL("kernel32.dll").NewProc("LocalFree")
	var text *uint16
	r, _, callErr := convert.Call(sid, uintptr(unsafe.Pointer(&text)))
	if r == 0 {
		return "", callErr
	}
	defer localFree.Call(uintptr(unsafe.Pointer(text)))
	return syscall.UTF16ToString((*[1 << 20]uint16)(unsafe.Pointer(text))[:]), nil
}

func tokenIdentity() (string, []string, error) {
	process, err := syscall.GetCurrentProcess()
	if err != nil {
		return "", nil, err
	}
	var token syscall.Token
	if err := syscall.OpenProcessToken(process, syscall.TOKEN_QUERY, &token); err != nil {
		return "", nil, err
	}
	defer token.Close()
	appBuffer, err := queryToken(token, tokenAppContainerSid)
	if err != nil {
		return "", nil, err
	}
	if len(appBuffer) < int(unsafe.Sizeof(uintptr(0))) {
		return "", nil, errors.New("invalid AppContainer SID buffer")
	}
	appSID, err := sidText(*(*uintptr)(unsafe.Pointer(&appBuffer[0])))
	if err != nil {
		return "", nil, err
	}
	buffer, err := queryToken(token, tokenCapabilities)
	if err != nil {
		return "", nil, err
	}
	count := *(*uint32)(unsafe.Pointer(&buffer[0]))
	// TOKEN_GROUPS aligns its first SID_AND_ATTRIBUTES to pointer alignment on
	// 64-bit Windows; the DWORD count alone is not the entry offset.
	headerSize := unsafe.Offsetof(struct {
		count uint32
		entry syscall.SIDAndAttributes
	}{}.entry)
	entrySize := unsafe.Sizeof(syscall.SIDAndAttributes{})
	if uintptr(len(buffer)) < headerSize || uintptr(count) > (uintptr(len(buffer))-headerSize)/entrySize {
		return "", nil, errors.New("invalid token capabilities buffer")
	}
	result := make([]string, 0, count)
	for i := uint32(0); i < count; i++ {
		entry := (*syscall.SIDAndAttributes)(unsafe.Pointer(&buffer[uintptr(headerSize)+uintptr(i)*entrySize]))
		text, err := sidText(uintptr(unsafe.Pointer(entry.Sid)))
		if err != nil {
			return "", nil, err
		}
		result = append(result, text)
	}
	return appSID, result, nil
}

func run() (returnErr error) {
	if len(os.Args) != 5 {
		return errors.New("usage: probe <expected-appcontainer-sid> <sentinel> <loopback-address> <work>")
	}
	expectedSID, sentinel, listener, work := os.Args[1], os.Args[2], os.Args[3], os.Args[4]
	report := probeReport{Schema: "aifi45.notice-isolation-probe/v1", NetworkCapabilitySIDs: []string{}}
	reportPath := filepath.Join(work, "probe-report.json")
	defer func() {
		// The launcher reads this owned file only after the process and all of its
		// children have exited. It contains probe diagnostics, never host file contents.
		if returnErr != nil {
			report.Failure = returnErr.Error()
		}
		if data, err := json.MarshalIndent(report, "", "  "); err == nil {
			_ = os.WriteFile(reportPath, append(data, '\n'), 0600)
		}
	}()

	report.EnvironmentExact, report.EnvironmentKeys = environmentExact()
	if !report.EnvironmentExact {
		return errors.New("environment whitelist mismatch")
	}
	appSID, capabilities, err := tokenIdentity()
	if err != nil {
		return fmt.Errorf("query own token: %w", err)
	}
	report.AppContainerSIDMatched = strings.EqualFold(appSID, expectedSID)
	blockedCapabilities := map[string]bool{
		"S-1-15-3-1": true, // internetClient
		"S-1-15-3-2": true, // internetClientServer
		"S-1-15-3-3": true, // privateNetworkClientServer
	}
	for _, sid := range capabilities {
		if blockedCapabilities[strings.ToUpper(sid)] {
			report.NetworkCapabilitySIDs = append(report.NetworkCapabilitySIDs, sid)
		}
	}
	// The launcher requested zero capabilities. Require the effective token to
	// agree, not merely to omit the three commonly used network SIDs.
	if len(capabilities) != 0 {
		return fmt.Errorf("effective token has %d unexpected capabilities", len(capabilities))
	}
	if !report.AppContainerSIDMatched || len(report.NetworkCapabilitySIDs) != 0 {
		return errors.New("effective AppContainer token or empty network capability check failed")
	}

	owned := filepath.Join(work, "probe-owned.txt")
	if err := os.WriteFile(owned, []byte("owned-probe\n"), 0600); err != nil {
		return err
	}
	if content, err := os.ReadFile(owned); err == nil && string(content) == "owned-probe\n" {
		report.OwnFileRoundTrip = true
	}
	if !report.OwnFileRoundTrip {
		return errors.New("owned-file round trip failed")
	}
	if _, err := os.ReadFile(sentinel); errors.Is(err, fs.ErrPermission) {
		report.SentinelReadDenied = true
	}
	if file, err := os.OpenFile(sentinel, os.O_WRONLY|os.O_APPEND, 0); err == nil {
		_ = file.Close()
	} else if errors.Is(err, fs.ErrPermission) {
		report.SentinelWriteDenied = true
	}
	if !report.SentinelReadDenied || !report.SentinelWriteDenied {
		return errors.New("outside-sentinel access was not denied")
	}

	connection, err := net.DialTimeout("tcp", listener, 3*time.Second)
	if err == nil {
		_ = connection.Close()
		return errors.New("loopback connection unexpectedly succeeded")
	}
	var networkError net.Error
	if !errors.As(err, &networkError) || !networkError.Timeout() {
		report.LoopbackRefused = true
		report.LoopbackError = err.Error()
	}
	if !report.LoopbackRefused {
		return errors.New("loopback attempt timed out instead of being refused")
	}

	return nil
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err.Error())
		os.Exit(1)
	}
}
