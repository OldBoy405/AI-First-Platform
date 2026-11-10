//go:build windows

// Command runner is a one-shot, offline AppContainer execution prototype.
// It creates only random children beneath --parent and runs an effective-isolation
// probe. This revision is synthetic-probe only: --target-binary / --target-sha256 are
// refused, so there is deliberately no code path that executes a real test binary.
// It never accepts a directory to recursively delete.
//
// Evidence discipline: fields the launcher asserts about itself live under
// `launcherAsserted`; fields read out of the target process live under
// `targetToken`; fields the target itself produced live under `probe`. Mixing
// the three is how a self-reported constant ends up looking like a measurement.
package main

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"syscall"
	"time"
	"unicode/utf16"
	"unsafe"
)

const (
	createSuspended                         = 0x00000004
	createNewProcessGroup                   = 0x00000200
	createUnicodeEnvironment                = 0x00000400
	createNoWindow                          = 0x08000000
	extendedStartupInfoPresent              = 0x00080000
	startfUseStdHandles                     = 0x00000100
	procThreadAttributeSecurityCapabilities = 0x00020009
	procThreadAttributeHandleList           = 0x00020002
	jobClassExtendedLimitInformation        = 9
	jobClassBasicAccountingInformation      = 1
	jobObjectLimitKillOnJobClose            = 0x00002000
	waitTimeout                             = 0x00000102
	genericAll                              = 0x10000000
	genericRead                             = 0x80000000
	genericWrite                            = 0x40000000
	genericExecute                          = 0x20000000
	deleteAccess                            = 0x00010000
	grantAccess                             = 1
	noInheritance                           = 0
	subContainersAndObjectsInherit          = 3
	trusteeIsSID                            = 0
	trusteeIsUser                           = 1
	trusteeIsGroup                          = 2
	seFileObject                            = 1
	daclSecurityInformation                 = 0x00000004
	protectedDaclSecurityInformation        = 0x80000000
	tokenIsAppContainer                     = 29
	tokenCapabilities                       = 30
	tokenAppContainerSid                    = 31
	tokenIntegrityLevel                     = 25
	createNew                               = 1
	openExisting                            = 3
	fileShareRead                           = 1
	fileShareWrite                          = 2
	fileShareDelete                         = 4
	fileFlagBackupSemantics                 = 0x02000000
	fileAttributeNormal                     = 0x00000080
)

var (
	userenv                           = syscall.NewLazyDLL("userenv.dll")
	advapi32                          = syscall.NewLazyDLL("advapi32.dll")
	kernel32                          = syscall.NewLazyDLL("kernel32.dll")
	createAppContainerProfile         = userenv.NewProc("CreateAppContainerProfile")
	freeSID                           = advapi32.NewProc("FreeSid")
	convertSIDToStringSID             = advapi32.NewProc("ConvertSidToStringSidW")
	localFree                         = kernel32.NewProc("LocalFree")
	convertSDDLToSecurityDescriptor   = advapi32.NewProc("ConvertStringSecurityDescriptorToSecurityDescriptorW")
	createDirectory                   = kernel32.NewProc("CreateDirectoryW")
	createFile                        = kernel32.NewProc("CreateFileW")
	getFinalPathNameByHandle          = kernel32.NewProc("GetFinalPathNameByHandleW")
	createJobObject                   = kernel32.NewProc("CreateJobObjectW")
	setInformationJobObject           = kernel32.NewProc("SetInformationJobObject")
	queryInformationJobObject         = kernel32.NewProc("QueryInformationJobObject")
	assignProcessToJobObject          = kernel32.NewProc("AssignProcessToJobObject")
	terminateJobObject                = kernel32.NewProc("TerminateJobObject")
	initializeProcThreadAttributeList = kernel32.NewProc("InitializeProcThreadAttributeList")
	updateProcThreadAttribute         = kernel32.NewProc("UpdateProcThreadAttribute")
	deleteProcThreadAttributeList     = kernel32.NewProc("DeleteProcThreadAttributeList")
)

type securityAttributes struct {
	length             uint32
	securityDescriptor uintptr
	inheritHandle      uint32
}

type startupInfoEx struct {
	startup       syscall.StartupInfo
	attributeList *byte
}

type securityCapabilities struct {
	appContainerSID uintptr
	capabilities    uintptr
	capabilityCount uint32
	reserved        uint32
}

type trustee struct {
	multipleTrustee          *trustee
	multipleTrusteeOperation uint32
	trusteeForm              uint32
	trusteeType              uint32
	name                     uintptr
}

type explicitAccess struct {
	accessPermissions uint32
	accessMode        uint32
	inheritance       uint32
	trustee           trustee
}

type jobObjectBasicLimitInformation struct {
	perProcessUserTimeLimit uint64
	perJobUserTimeLimit     uint64
	limitFlags              uint32
	_                       uint32
	minimumWorkingSetSize   uintptr
	maximumWorkingSetSize   uintptr
	activeProcessLimit      uint32
	_                       uint32
	affinity                uintptr
	priorityClass           uint32
	schedulingClass         uint32
}

type ioCounters struct {
	readOperationCount  uint64
	writeOperationCount uint64
	otherOperationCount uint64
	readTransferCount   uint64
	writeTransferCount  uint64
	otherTransferCount  uint64
}

type jobObjectExtendedLimitInformation struct {
	basicLimit            jobObjectBasicLimitInformation
	ioInfo                ioCounters
	processMemoryLimit    uintptr
	jobMemoryLimit        uintptr
	peakProcessMemoryUsed uintptr
	peakJobMemoryUsed     uintptr
}

type jobObjectBasicAccountingInformation struct {
	totalUserTime             uint64
	totalKernelTime           uint64
	thisPeriodTotalUserTime   uint64
	thisPeriodTotalKernelTime uint64
	totalPageFaultCount       uint32
	totalProcesses            uint32
	activeProcesses           uint32
	totalTerminatedProcesses  uint32
}

type fileIdentity struct {
	VolumeSerialNumber uint32 `json:"volumeSerialNumber"`
	FileIndexHigh      uint32 `json:"fileIndexHigh"`
	FileIndexLow       uint32 `json:"fileIndexLow"`
}

type resourcePlan struct {
	CanonicalParent string       `json:"canonicalParent"`
	ParentIdentity  fileIdentity `json:"parentIdentity"`
	RootName        string       `json:"rootName"`
	SentinelName    string       `json:"sentinelName"`
	ProfileName     string       `json:"profileName"`
}

type ownedResourceIdentity struct {
	RootRelativePath     string        `json:"rootRelativePath"`
	RootOwned            bool          `json:"rootOwned"`
	SentinelRelativePath string        `json:"sentinelRelativePath"`
	SentinelOwned        bool          `json:"sentinelOwned"`
	ProfileName          string        `json:"profileName"`
	ProfileOwned         bool          `json:"profileOwned"`
	RootIdentity         *fileIdentity `json:"rootIdentity,omitempty"`
	SentinelIdentity     *fileIdentity `json:"sentinelIdentity,omitempty"`
}

type phaseEvidence struct {
	Kind                  string                `json:"kind"`
	BinarySHA256          string                `json:"binarySha256"`
	AppContainerSID       string                `json:"appContainerSid"`
	LauncherAsserted      launcherAsserted      `json:"launcherAsserted"`
	TargetToken           tokenEvidence         `json:"targetToken"`
	ProcessStarted        bool                  `json:"processStarted"`
	ProcessExitCode       *uint32               `json:"processExitCode"`
	JobActiveAfterExit    *uint32               `json:"jobActiveAfterExit"`
	JobEmptyConfirmed     bool                  `json:"jobEmptyConfirmed"`
	RuntimePreserved      bool                  `json:"runtimePreserved"`
	PreserveAll           bool                  `json:"preserveAll"`
	Resources             ownedResourceIdentity `json:"resources"`
	JobHandleDisposition  string                `json:"jobHandleDisposition,omitempty"`
	DescendantTermination string                `json:"descendantTermination,omitempty"`
	Probe                 *probeEvidence        `json:"probe,omitempty"`
	StdoutBytes           int64                 `json:"stdoutBytes"`
	StderrBytes           int64                 `json:"stderrBytes"`
	StderrSHA256          string                `json:"stderrSha256"`
}

type launchSafety struct {
	ProcessCreated    bool
	JobEmptyConfirmed bool
	PreserveRuntime   bool
}

// launcherAsserted 是本帧启动器对**自身**行为的断言：它证明「我们做了 X」，
// 不证明「目标只继承了这些」。复核曾指出这些字段若混在 targetToken 下会被误读成实测值。
type launcherAsserted struct {
	HandleListApplied    bool   `json:"handleListApplied"`
	InheritedHandleCount int    `json:"inheritedHandleCount"`
	EnvironmentBlockKeys int    `json:"environmentBlockKeys"`
	Note                 string `json:"note"`
}

type tokenEvidence struct {
	Verified        bool   `json:"verified"`
	IsAppContainer  bool   `json:"isAppContainer"`
	ExpectedSID     string `json:"expectedSid"`
	ActualSID       string `json:"actualSid"`
	CapabilityCount uint32 `json:"capabilityCount"`
	IntegritySID    string `json:"integritySid"`
}

type probeEvidence struct {
	AppContainerSIDMatched bool     `json:"appContainerSidMatched"`
	NetworkCapabilitySIDs  []string `json:"networkCapabilitySids"`
	EnvironmentKeys        []string `json:"environmentKeys"`
	EnvironmentExact       bool     `json:"environmentExact"`
	OwnFileRoundTrip       bool     `json:"ownFileRoundTrip"`
	SentinelReadDenied     bool     `json:"sentinelReadDenied"`
	SentinelWriteDenied    bool     `json:"sentinelWriteDenied"`
	LoopbackRefused        bool     `json:"loopbackRefused"`
	LoopbackError          string   `json:"loopbackError,omitempty"`
	Failure                string   `json:"failure,omitempty"`
}

type evidenceRecorder struct {
	file     *os.File
	identity fileIdentity
}

type evidence struct {
	Schema             string         `json:"schema"`
	CanonicalParent    string         `json:"canonicalParent"`
	ParentIdentity     fileIdentity   `json:"parentIdentity"`
	EvidenceIdentity   fileIdentity   `json:"evidenceIdentity"`
	StartedAt          time.Time      `json:"startedAt"`
	FinishedAt         time.Time      `json:"finishedAt,omitempty"`
	Status             string         `json:"status"`
	Failure            string         `json:"failure,omitempty"`
	Mechanism          string         `json:"mechanism"`
	EnvironmentKeys    []string       `json:"environmentKeys"`
	ProbeSourceSHA256  string         `json:"probeSourceSha256"`
	ProbeBinarySHA256  string         `json:"probeBinarySha256"`
	ProbeBinaryBinding string         `json:"probeBinaryBinding"`
	GoToolchain        string         `json:"goToolchain,omitempty"`
	Probe              *phaseEvidence `json:"probe,omitempty"`
}

type currentUser struct {
	sid    uintptr
	buffer []byte
}

func randomName(prefix string) (string, error) {
	bytes := make([]byte, 16)
	if _, err := rand.Read(bytes); err != nil {
		return "", err
	}
	return prefix + hex.EncodeToString(bytes), nil
}

// fileIdentityFromHandle 必须用 syscall.ByHandleFileInformation，不能自建结构体：
// FILETIME 是两个 uint32（4 字节对齐），建成 Go uint64 会改变后续字段偏移，
// 使卷序列号/文件 ID 全部读错，而错的身份会静默把「已替换」当成「同一个」。
func fileIdentityFromHandle(handle syscall.Handle) (fileIdentity, error) {
	var info syscall.ByHandleFileInformation
	if err := syscall.GetFileInformationByHandle(handle, &info); err != nil {
		return fileIdentity{}, fmt.Errorf("GetFileInformationByHandle: %w", err)
	}
	return fileIdentity{VolumeSerialNumber: info.VolumeSerialNumber, FileIndexHigh: info.FileIndexHigh, FileIndexLow: info.FileIndexLow}, nil
}

func openWindowsFile(path string, access, share, creation, flags uint32, attributes *securityAttributes) (*os.File, error) {
	path16, _ := syscall.UTF16PtrFromString(path)
	var security uintptr
	if attributes != nil {
		security = uintptr(unsafe.Pointer(attributes))
	}
	r, _, callErr := createFile.Call(uintptr(unsafe.Pointer(path16)), uintptr(access), uintptr(share), security, uintptr(creation), uintptr(flags), 0)
	runtime.KeepAlive(path16)
	runtime.KeepAlive(attributes)
	if r == ^uintptr(0) {
		return nil, fmt.Errorf("CreateFileW %s: %w", path, callErr)
	}
	file := os.NewFile(r, path)
	if file == nil {
		syscall.CloseHandle(syscall.Handle(r))
		return nil, errors.New("os.NewFile returned nil")
	}
	return file, nil
}

func canonicalParent(path string) (string, fileIdentity, error) {
	file, err := openWindowsFile(path, 0, fileShareRead|fileShareWrite|fileShareDelete, openExisting, fileFlagBackupSemantics, nil)
	if err != nil {
		return "", fileIdentity{}, err
	}
	handle := syscall.Handle(file.Fd())
	defer file.Close()
	identity, err := fileIdentityFromHandle(handle)
	if err != nil {
		return "", fileIdentity{}, err
	}
	buffer := make([]uint16, 32768)
	length, _, callErr := getFinalPathNameByHandle.Call(uintptr(handle), uintptr(unsafe.Pointer(&buffer[0])), uintptr(len(buffer)), 0)
	runtime.KeepAlive(buffer)
	if length == 0 || length >= uintptr(len(buffer)) {
		return "", fileIdentity{}, fmt.Errorf("GetFinalPathNameByHandleW: %w", callErr)
	}
	return syscall.UTF16ToString(buffer[:length]), identity, nil
}

// dosPath 把 GetFinalPathNameByHandleW 返回的扩展长度路径还原为 DOS 形式。
// CreateProcessW 的 lpCurrentDirectory 未在 `\\?\` 形式下验证，因此启动时传 DOS 形式，
// 并在启动前用文件身份比对证明它与已创建的对象是同一个。
func dosPath(extended string) (string, error) {
	const uncPrefix = `\\?\UNC\`
	const drivePrefix = `\\?\`
	var out string
	switch {
	case strings.HasPrefix(extended, uncPrefix):
		out = `\\` + extended[len(uncPrefix):]
	case strings.HasPrefix(extended, drivePrefix):
		out = extended[len(drivePrefix):]
	default:
		out = extended
	}
	// 只接受 X:\ 或 \\server\share 两种 DOS 形式：GLOBALROOT/Volume{GUID} 等去掉前缀后会变成
	// 相对路径，不能让它们以「已转成 DOS 形式」的身份进入启动路径。
	if len(out) >= 3 && out[1] == ':' && (out[2] == '\\' || out[2] == '/') && ((out[0] >= 'A' && out[0] <= 'Z') || (out[0] >= 'a' && out[0] <= 'z')) {
		return out, nil
	}
	if strings.HasPrefix(out, `\\`) && len(out) > 2 {
		return out, nil
	}
	return "", fmt.Errorf("path is not an absolute DOS path after conversion: %s", extended)
}

func (recorder *evidenceRecorder) write(eventType string, payload any) error {
	data, err := json.Marshal(struct {
		Time    time.Time `json:"time"`
		Type    string    `json:"type"`
		Payload any       `json:"payload"`
	}{Time: time.Now().UTC(), Type: eventType, Payload: payload})
	if err != nil {
		return err
	}
	if _, err := recorder.file.Write(append(data, '\n')); err != nil {
		return err
	}
	return recorder.file.Sync()
}

func openEvidenceRecorder(path string, plan resourcePlan) (*evidenceRecorder, error) {
	file, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
	if err != nil {
		return nil, err
	}
	recorder := &evidenceRecorder{file: file}
	identity, err := fileIdentityFromHandle(syscall.Handle(file.Fd()))
	if err != nil {
		file.Close()
		return nil, err
	}
	recorder.identity = identity
	if err := recorder.write("resource-plan", plan); err != nil {
		file.Close()
		return nil, err
	}
	return recorder, nil
}

func sha256File(name string) (string, int64, error) {
	file, err := os.Open(name)
	if err != nil {
		return "", 0, err
	}
	defer file.Close()
	hash := sha256.New()
	size, err := io.Copy(hash, file)
	if err != nil {
		return "", 0, err
	}
	return hex.EncodeToString(hash.Sum(nil)), size, nil
}

// sha256TextFile 按工作区哈希纪律先做 CRLF→LF 规范化：文本文件的原始字节哈希
// 会随 checkout 的 autocrlf 漂移，不能当源码快照证明。
func sha256TextFile(name string) (string, error) {
	data, err := os.ReadFile(name)
	if err != nil {
		return "", err
	}
	normalized := strings.ReplaceAll(string(data), "\r\n", "\n")
	sum := sha256.Sum256([]byte(normalized))
	return hex.EncodeToString(sum[:]), nil
}

func hashOpenFile(file *os.File) (string, error) {
	if _, err := file.Seek(0, io.SeekStart); err != nil {
		return "", err
	}
	hash := sha256.New()
	if _, err := io.Copy(hash, file); err != nil {
		return "", err
	}
	return hex.EncodeToString(hash.Sum(nil)), nil
}

func validSHA256(value string) bool {
	if len(value) != 64 {
		return false
	}
	_, err := hex.DecodeString(value)
	return err == nil
}

// copyExclusive returns a read-only guard that denies write/delete sharing.
// The original CREATE_NEW handle remains open until this guard is active, so
// there is no close/reopen interval in which the copied image is unguarded.
func copyExclusive(source, destination, expectedSHA string) (string, *os.File, fileIdentity, error) {
	if !validSHA256(expectedSHA) {
		return "", nil, fileIdentity{}, errors.New("coordinator SHA-256 must contain exactly 64 hexadecimal characters")
	}
	input, err := openWindowsFile(source, genericRead, fileShareRead, openExisting, fileAttributeNormal, nil)
	if err != nil {
		return "", nil, fileIdentity{}, err
	}
	defer input.Close()
	sourceHash, err := hashOpenFile(input)
	if err != nil || !strings.EqualFold(sourceHash, expectedSHA) {
		return "", nil, fileIdentity{}, errors.New("probe source does not match coordinator SHA-256")
	}
	if _, err := input.Seek(0, io.SeekStart); err != nil {
		return "", nil, fileIdentity{}, err
	}
	output, err := openWindowsFile(destination, genericRead|genericWrite, fileShareRead, createNew, fileAttributeNormal, nil)
	if err != nil {
		return "", nil, fileIdentity{}, err
	}
	if _, err := io.Copy(output, input); err != nil {
		output.Close()
		return "", nil, fileIdentity{}, err
	}
	if err := output.Sync(); err != nil {
		output.Close()
		return "", nil, fileIdentity{}, err
	}
	copiedHash, err := hashOpenFile(output)
	if err != nil || !strings.EqualFold(copiedHash, expectedSHA) {
		output.Close()
		return "", nil, fileIdentity{}, errors.New("copied probe hash mismatch")
	}
	outputIdentity, err := fileIdentityFromHandle(syscall.Handle(output.Fd()))
	if err != nil {
		output.Close()
		return "", nil, fileIdentity{}, err
	}
	// 必须先关闭写句柄再建只读 guard：openWindowsFile 的 share 不含 FILE_SHARE_WRITE，
	// 若写句柄仍开着，第二次 CreateFileW 会直接 ERROR_SHARING_VIOLATION。关闭后的窗口由
	// 「身份比对 + 用 guard 句柄重哈希」两道检查覆盖。
	if err := output.Close(); err != nil {
		return "", nil, fileIdentity{}, err
	}
	// guard 只共享读：它存在期间任何他人 open-for-write/delete 都会失败，
	// 所以 CreateProcessW 按路径打开镜像的窗口内路径不可被同 UID 替换。
	guard, err := openWindowsFile(destination, genericRead, fileShareRead, openExisting, fileAttributeNormal, nil)
	if err != nil {
		return "", nil, fileIdentity{}, err
	}
	identity, err := fileIdentityFromHandle(syscall.Handle(guard.Fd()))
	if err != nil {
		guard.Close()
		return "", nil, fileIdentity{}, err
	}
	if identity != outputIdentity {
		guard.Close()
		return "", nil, fileIdentity{}, errors.New("probe image identity changed while installing execution guard")
	}
	// 身份相同不足以证明字节未变：同 UID 可以在关闭写句柄到重开 guard 之间就地覆写内容，
	// 文件 ID 完全不变。因此下面必须用 guard 句柄把字节重新哈希一遍并与协调者钉值比对；
	// 但重哈希仍不证明 launch 那一刻的字节（窗口见 ISOLATION-REVIEW 的未解决项）。
	guardedHash, err := hashOpenFile(guard)
	if err != nil {
		guard.Close()
		return "", nil, fileIdentity{}, err
	}
	if !strings.EqualFold(guardedHash, expectedSHA) {
		guard.Close()
		return "", nil, fileIdentity{}, errors.New("probe image bytes changed before the read-only guard was established")
	}
	return copiedHash, guard, identity, nil
}

func getCurrentUser() (*currentUser, error) {
	process, err := syscall.GetCurrentProcess()
	if err != nil {
		return nil, err
	}
	var token syscall.Token
	if err := syscall.OpenProcessToken(process, syscall.TOKEN_QUERY, &token); err != nil {
		return nil, err
	}
	defer token.Close()
	var needed uint32
	_ = syscall.GetTokenInformation(token, syscall.TokenUser, nil, 0, &needed)
	if needed == 0 || needed > 1<<20 {
		return nil, errors.New("invalid current-user token size")
	}
	buffer := make([]byte, needed)
	if err := syscall.GetTokenInformation(token, syscall.TokenUser, &buffer[0], needed, &needed); err != nil {
		return nil, err
	}
	user := (*syscall.Tokenuser)(unsafe.Pointer(&buffer[0]))
	return &currentUser{sid: uintptr(unsafe.Pointer(user.User.Sid)), buffer: buffer}, nil
}

func sidString(sid uintptr) (string, error) {
	var text *uint16
	r, _, callErr := convertSIDToStringSID.Call(sid, uintptr(unsafe.Pointer(&text)))
	if r == 0 {
		return "", callErr
	}
	defer localFree.Call(uintptr(unsafe.Pointer(text)))
	return syscall.UTF16ToString((*[1 << 20]uint16)(unsafe.Pointer(text))[:]), nil
}

func createProfile(name string) (uintptr, string, string, bool, error) {
	name16, _ := syscall.UTF16PtrFromString(name)
	display16, _ := syscall.UTF16PtrFromString("AIFI45 one-shot NTF isolation")
	description16, _ := syscall.UTF16PtrFromString("No capabilities; disposable test execution")
	var sid uintptr
	hresult, _, _ := createAppContainerProfile.Call(
		uintptr(unsafe.Pointer(name16)), uintptr(unsafe.Pointer(display16)),
		uintptr(unsafe.Pointer(description16)), 0, 0, uintptr(unsafe.Pointer(&sid)))
	runtime.KeepAlive(name16)
	runtime.KeepAlive(display16)
	runtime.KeepAlive(description16)
	if int32(hresult) != 0 {
		// No profile was created, so the caller must not attempt deletion.
		return 0, name, "", false, fmt.Errorf("CreateAppContainerProfile HRESULT 0x%08x", uint32(hresult))
	}
	// Ownership begins immediately after successful creation. In particular,
	// SID conversion failure still returns ownership for the caller's cleanup.
	text, err := sidString(sid)
	return sid, name, text, true, err
}

func securityAttributesFromSDDL(sddl string) (*securityAttributes, uintptr, error) {
	sddl16, _ := syscall.UTF16PtrFromString(sddl)
	var descriptor uintptr
	r, _, callErr := convertSDDLToSecurityDescriptor.Call(uintptr(unsafe.Pointer(sddl16)), 1, uintptr(unsafe.Pointer(&descriptor)), 0)
	runtime.KeepAlive(sddl16)
	if r == 0 {
		return nil, 0, fmt.Errorf("ConvertStringSecurityDescriptorToSecurityDescriptorW: %w", callErr)
	}
	return &securityAttributes{length: uint32(unsafe.Sizeof(securityAttributes{})), securityDescriptor: descriptor}, descriptor, nil
}

// createDirectoryWithACL installs a protected DACL atomically with directory
// creation. There is no inherited-ACL window before the first child or target
// is created, and CreateDirectoryW fails rather than reusing an existing root.
// directorySddlTemplate 是受保护目录 DACL 的**唯一**模板（F2：此前格式串写了两份，
// 改一处忘另一处会让预验失效）。哨兵模板同理，只有一份。
const (
	directorySddlTemplate = "D:P(A;OICI;FA;;;%s)(A;OICI;%s;;;%s)"
	sentinelSddlTemplate  = "D:P(A;;FA;;;%s)"
)

// validateDirectoryAclTemplates 在创建任何持久资源之前先把 SDDL 模板解析一遍。
// 权限串写错（例如把删除权 SD 误写成 DE）只在 ConvertStringSecurityDescriptorToSecurityDescriptorW
// 运行时才暴露，而那时 profile/root/sentinel 已经建好，属于「先污染再失败」。
// 这里只用占位 SID 解析并立即 LocalFree，不创建任何对象。
func validateDirectoryAclTemplates() error {
	const dummyUser = "S-1-5-21-1111111111-2222222222-3333333333-1001"
	const dummyApp = "S-1-15-2-1"
	// 哨兵模板也一起验（F1）：它此前是唯一未经预验就拼出来的 SDDL，
	// 而它发生在 profile 与 root 都建好之后。
	sddls := []string{
		fmt.Sprintf(sentinelSddlTemplate, dummyUser),
		fmt.Sprintf(directorySddlTemplate, dummyUser, "GRGX", dummyApp),
		fmt.Sprintf(directorySddlTemplate, dummyUser, "GRGWGXSD", dummyApp),
	}
	for _, sddl := range sddls {
		_, descriptor, err := securityAttributesFromSDDL(sddl)
		if err != nil {
			return fmt.Errorf("SDDL template invalid for %q: %w", sddl, err)
		}
		localFree.Call(descriptor)
	}
	return nil
}

func createDirectoryWithACL(path string, user *currentUser, appSID uintptr, appRights string) error {
	userSID, err := sidString(user.sid)
	runtime.KeepAlive(user.buffer)
	if err != nil {
		return err
	}
	appSIDText, err := sidString(appSID)
	if err != nil {
		return err
	}
	sddl := fmt.Sprintf(directorySddlTemplate, userSID, appRights, appSIDText)
	attributes, descriptor, err := securityAttributesFromSDDL(sddl)
	if err != nil {
		return err
	}
	defer localFree.Call(descriptor)
	path16, _ := syscall.UTF16PtrFromString(path)
	r, _, callErr := createDirectory.Call(uintptr(unsafe.Pointer(path16)), uintptr(unsafe.Pointer(attributes)))
	runtime.KeepAlive(path16)
	runtime.KeepAlive(attributes)
	runtime.KeepAlive(user.buffer)
	if r == 0 {
		return fmt.Errorf("CreateDirectoryW with protected DACL: %w", callErr)
	}
	return nil
}

func createSentinel(path, content string, user *currentUser) (*os.File, fileIdentity, error) {
	userSID, err := sidString(user.sid)
	runtime.KeepAlive(user.buffer)
	if err != nil {
		return nil, fileIdentity{}, err
	}
	attributes, descriptor, err := securityAttributesFromSDDL(fmt.Sprintf(sentinelSddlTemplate, userSID))
	if err != nil {
		return nil, fileIdentity{}, err
	}
	defer localFree.Call(descriptor)
	file, err := openWindowsFile(path, genericRead|genericWrite, fileShareRead, createNew, fileAttributeNormal, attributes)
	runtime.KeepAlive(attributes)
	runtime.KeepAlive(user.buffer)
	if err != nil {
		return nil, fileIdentity{}, err
	}
	if _, err := file.WriteString(content); err != nil {
		return file, fileIdentity{}, err
	}
	if err := file.Sync(); err != nil {
		return file, fileIdentity{}, err
	}
	identity, err := fileIdentityFromHandle(syscall.Handle(file.Fd()))
	if err != nil {
		return file, fileIdentity{}, err
	}
	return file, identity, nil
}

func createJob() (syscall.Handle, error) {
	r, _, callErr := createJobObject.Call(0, 0)
	if r == 0 {
		return 0, callErr
	}
	job := syscall.Handle(r)
	limits := jobObjectExtendedLimitInformation{}
	limits.basicLimit.limitFlags = jobObjectLimitKillOnJobClose
	r, _, callErr = setInformationJobObject.Call(uintptr(job), jobClassExtendedLimitInformation,
		uintptr(unsafe.Pointer(&limits)), unsafe.Sizeof(limits))
	if r == 0 {
		syscall.CloseHandle(job)
		return 0, callErr
	}
	return job, nil
}

func activeProcesses(job syscall.Handle) (uint32, error) {
	var accounting jobObjectBasicAccountingInformation
	var returned uint32
	r, _, callErr := queryInformationJobObject.Call(uintptr(job), jobClassBasicAccountingInformation,
		uintptr(unsafe.Pointer(&accounting)), unsafe.Sizeof(accounting), uintptr(unsafe.Pointer(&returned)))
	if r == 0 {
		return 0, callErr
	}
	return accounting.activeProcesses, nil
}

func environmentBlock(root string) ([]uint16, []string, error) {
	home := filepath.Join(root, "home")
	values := map[string]string{
		"SystemRoot":   `C:\Windows`,
		"WINDIR":       `C:\Windows`,
		"PATH":         `C:\Windows\System32`,
		"HOME":         home,
		"USERPROFILE":  home,
		"APPDATA":      home,
		"LOCALAPPDATA": home,
		"TEMP":         filepath.Join(root, "tmp"),
		"TMP":          filepath.Join(root, "tmp"),
		"GOCACHE":      filepath.Join(root, "cache"),
		"GOPATH":       filepath.Join(root, "gopath"),
		"GOPROXY":      "off",
		"GOSUMDB":      "off",
		"GOTOOLCHAIN":  "local",
		"GOENV":        "off",
		"GOWORK":       "off",
		"GOFLAGS":      "-mod=readonly",
		"GOTELEMETRY":  "off",
		"CGO_ENABLED":  "0",
		"GOOS":         "windows",
		"GOARCH":       "amd64",
	}
	keys := make([]string, 0, len(values))
	for key := range values {
		keys = append(keys, key)
	}
	sort.Slice(keys, func(i, j int) bool { return strings.ToUpper(keys[i]) < strings.ToUpper(keys[j]) })
	var builder strings.Builder
	for _, key := range keys {
		builder.WriteString(key)
		builder.WriteByte('=')
		builder.WriteString(values[key])
		builder.WriteByte(0)
	}
	builder.WriteByte(0)
	return utf16.Encode([]rune(builder.String())), keys, nil
}

func quoteArgument(value string) string {
	if value != "" && !strings.ContainsAny(value, " \t\n\v\"") {
		return value
	}
	var builder strings.Builder
	builder.WriteByte('"')
	backslashes := 0
	for _, r := range value {
		if r == '\\' {
			backslashes++
			continue
		}
		if r == '"' {
			builder.WriteString(strings.Repeat("\\", backslashes*2+1))
			builder.WriteRune(r)
			backslashes = 0
			continue
		}
		builder.WriteString(strings.Repeat("\\", backslashes))
		backslashes = 0
		builder.WriteRune(r)
	}
	builder.WriteString(strings.Repeat("\\", backslashes*2))
	builder.WriteByte('"')
	return builder.String()
}

func inheritable(file *os.File) error {
	r, _, callErr := kernel32.NewProc("SetHandleInformation").Call(file.Fd(), 1, 1)
	if r == 0 {
		return callErr
	}
	return nil
}

func queryTargetToken(token syscall.Token, class uint32) ([]byte, error) {
	var needed uint32
	_ = syscall.GetTokenInformation(token, class, nil, 0, &needed)
	if needed == 0 || needed > 1<<20 {
		return nil, fmt.Errorf("invalid target token information size for class %d", class)
	}
	buffer := make([]byte, needed)
	if err := syscall.GetTokenInformation(token, class, &buffer[0], needed, &needed); err != nil {
		return nil, err
	}
	return buffer, nil
}

// verifyTargetToken runs in the trusted launcher while the target primary
// thread is still suspended. A separate probe's token is never a substitute.
func verifyTargetToken(process syscall.Handle, expectedAppSID uintptr, result *tokenEvidence) error {
	expected, err := sidString(expectedAppSID)
	if err != nil {
		return err
	}
	result.ExpectedSID = expected
	var token syscall.Token
	if err := syscall.OpenProcessToken(process, syscall.TOKEN_QUERY, &token); err != nil {
		return fmt.Errorf("open suspended target token: %w", err)
	}
	defer token.Close()

	isBuffer, err := queryTargetToken(token, tokenIsAppContainer)
	if err != nil || len(isBuffer) < 4 {
		return errors.New("query target TokenIsAppContainer")
	}
	result.IsAppContainer = *(*uint32)(unsafe.Pointer(&isBuffer[0])) != 0
	if !result.IsAppContainer {
		return errors.New("target is not an AppContainer process")
	}

	appBuffer, err := queryTargetToken(token, tokenAppContainerSid)
	if err != nil || len(appBuffer) < int(unsafe.Sizeof(uintptr(0))) {
		return errors.New("query target TokenAppContainerSid")
	}
	result.ActualSID, err = sidString(*(*uintptr)(unsafe.Pointer(&appBuffer[0])))
	runtime.KeepAlive(appBuffer)
	if err != nil {
		return err
	}
	if !strings.EqualFold(result.ActualSID, expected) {
		return errors.New("target AppContainer SID mismatch")
	}

	capBuffer, err := queryTargetToken(token, tokenCapabilities)
	if err != nil || len(capBuffer) < 4 {
		return errors.New("query target TokenCapabilities")
	}
	result.CapabilityCount = *(*uint32)(unsafe.Pointer(&capBuffer[0]))
	headerSize := unsafe.Offsetof(struct {
		count uint32
		entry syscall.SIDAndAttributes
	}{}.entry)
	entrySize := unsafe.Sizeof(syscall.SIDAndAttributes{})
	if uintptr(len(capBuffer)) < headerSize || uintptr(result.CapabilityCount) > (uintptr(len(capBuffer))-headerSize)/entrySize {
		return errors.New("invalid target capabilities buffer")
	}
	if result.CapabilityCount != 0 {
		return errors.New("target has unexpected capabilities")
	}

	integrityBuffer, err := queryTargetToken(token, tokenIntegrityLevel)
	if err != nil || len(integrityBuffer) < int(unsafe.Sizeof(syscall.SIDAndAttributes{})) {
		return errors.New("query target TokenIntegrityLevel")
	}
	integrity := (*syscall.SIDAndAttributes)(unsafe.Pointer(&integrityBuffer[0]))
	result.IntegritySID, err = sidString(uintptr(unsafe.Pointer(integrity.Sid)))
	runtime.KeepAlive(integrityBuffer)
	if err != nil {
		return err
	}
	if !strings.EqualFold(result.IntegritySID, "S-1-16-4096") {
		return errors.New("target integrity is not Low")
	}
	result.Verified = true
	return nil
}

func terminateSuspendedProcess(process syscall.Handle) error {
	r, _, callErr := kernel32.NewProc("TerminateProcess").Call(uintptr(process), 1)
	if r == 0 {
		return fmt.Errorf("TerminateProcess: %w", callErr)
	}
	wait, _, callErr := kernel32.NewProc("WaitForSingleObject").Call(uintptr(process), 5000)
	if wait != 0 {
		return fmt.Errorf("wait for terminated suspended process (status %d): %w", wait, callErr)
	}
	return nil
}

func terminateAndDrainJob(job syscall.Handle) error {
	r, _, callErr := terminateJobObject.Call(uintptr(job), 1)
	if r == 0 {
		return fmt.Errorf("TerminateJobObject: %w", callErr)
	}
	deadline := time.Now().Add(3 * time.Second)
	for {
		active, err := activeProcesses(job)
		if err != nil {
			return fmt.Errorf("confirm Job drainage: %w", err)
		}
		if active == 0 {
			return nil
		}
		if time.Now().After(deadline) {
			return errors.New("Job did not drain within the bounded interval")
		}
		time.Sleep(10 * time.Millisecond)
	}
}

func failAfterLaunch(job syscall.Handle, safety *launchSafety, cause error) error {
	if err := terminateAndDrainJob(job); err != nil {
		safety.PreserveRuntime = true
		safety.JobEmptyConfirmed = false
		return fmt.Errorf("%v; owned Job drainage unconfirmed: %v", cause, err)
	}
	safety.JobEmptyConfirmed = true
	return cause
}

func launch(executable, work string, arguments []string, environment []uint16, appSID uintptr, timeout time.Duration, tokenResult *tokenEvidence, safety *launchSafety, imageGuard *os.File, launcherOut *launcherAsserted) (*uint32, *uint32, error) {
	job, err := createJob()
	if err != nil {
		return nil, nil, fmt.Errorf("create owned job: %w", err)
	}
	defer func() {
		// If drainage is unconfirmed, do not pretend that closing the last handle
		// proves cleanup. KILL_ON_JOB_CLOSE may still act at process teardown; the
		// resulting handle/lifetime risk is explicitly left for reviewed follow-up.
		if !safety.PreserveRuntime {
			syscall.CloseHandle(job)
		}
	}()

	var size uintptr
	_, _, _ = initializeProcThreadAttributeList.Call(0, 2, 0, uintptr(unsafe.Pointer(&size)))
	if size == 0 || size > 1<<20 {
		return nil, nil, errors.New("invalid process attribute-list size")
	}
	buffer := make([]byte, size)
	r, _, callErr := initializeProcThreadAttributeList.Call(uintptr(unsafe.Pointer(&buffer[0])), 2, 0, uintptr(unsafe.Pointer(&size)))
	if r == 0 {
		return nil, nil, callErr
	}
	var capabilities securityCapabilities
	var inheritedHandles [3]syscall.Handle
	defer func() {
		deleteProcThreadAttributeList.Call(uintptr(unsafe.Pointer(&buffer[0])))
		// Keep every backing allocation alive through attribute-list destruction,
		// not merely until UpdateProcThreadAttribute or CreateProcessW returns.
		runtime.KeepAlive(buffer)
		runtime.KeepAlive(capabilities)
		runtime.KeepAlive(inheritedHandles)
	}()
	capabilities = securityCapabilities{appContainerSID: appSID}
	r, _, callErr = updateProcThreadAttribute.Call(uintptr(unsafe.Pointer(&buffer[0])), 0,
		procThreadAttributeSecurityCapabilities, uintptr(unsafe.Pointer(&capabilities)),
		unsafe.Sizeof(capabilities), 0, 0)
	if r == 0 {
		return nil, nil, callErr
	}

	stdin, err := os.OpenFile("NUL", os.O_RDONLY, 0)
	if err != nil {
		return nil, nil, err
	}
	defer stdin.Close()
	stdout, err := os.OpenFile(filepath.Join(work, "stdout.bin"), os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
	if err != nil {
		return nil, nil, err
	}
	defer stdout.Close()
	stderr, err := os.OpenFile(filepath.Join(work, "stderr.bin"), os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
	if err != nil {
		return nil, nil, err
	}
	defer stderr.Close()
	for _, file := range []*os.File{stdin, stdout, stderr} {
		if err := inheritable(file); err != nil {
			return nil, nil, err
		}
	}
	// With bInheritHandles=TRUE, explicitly restrict inheritance to exactly the
	// three owned stdio handles. No launcher, listener, Job or token handle is
	// eligible merely because it happens to be inheritable.
	inheritedHandles = [3]syscall.Handle{syscall.Handle(stdin.Fd()), syscall.Handle(stdout.Fd()), syscall.Handle(stderr.Fd())}
	r, _, callErr = updateProcThreadAttribute.Call(uintptr(unsafe.Pointer(&buffer[0])), 0,
		procThreadAttributeHandleList, uintptr(unsafe.Pointer(&inheritedHandles[0])),
		unsafe.Sizeof(inheritedHandles), 0, 0)
	if r == 0 {
		return nil, nil, callErr
	}
	// 只写启动器自己的出参：这些是「我们做了什么」，不是目标 token 的实测值。
	if launcherOut != nil {
		launcherOut.HandleListApplied = true
		launcherOut.InheritedHandleCount = len(inheritedHandles)
	}
	startup := startupInfoEx{attributeList: &buffer[0]}
	startup.startup.Cb = uint32(unsafe.Sizeof(startup))
	startup.startup.Flags = startfUseStdHandles
	startup.startup.StdInput = syscall.Handle(stdin.Fd())
	startup.startup.StdOutput = syscall.Handle(stdout.Fd())
	startup.startup.StdErr = syscall.Handle(stderr.Fd())
	var process syscall.ProcessInformation
	application16, _ := syscall.UTF16PtrFromString(executable)
	allArguments := append([]string{executable}, arguments...)
	commandLine := strings.Join(func() []string {
		result := make([]string, len(allArguments))
		for i, argument := range allArguments {
			result[i] = quoteArgument(argument)
		}
		return result
	}(), " ")
	command16, _ := syscall.UTF16PtrFromString(commandLine)
	work16, _ := syscall.UTF16PtrFromString(work)
	r, _, callErr = kernel32.NewProc("CreateProcessW").Call(
		uintptr(unsafe.Pointer(application16)), uintptr(unsafe.Pointer(command16)), 0, 0, 1,
		createSuspended|createNewProcessGroup|createUnicodeEnvironment|createNoWindow|extendedStartupInfoPresent,
		uintptr(unsafe.Pointer(&environment[0])), uintptr(unsafe.Pointer(work16)),
		uintptr(unsafe.Pointer(&startup)), uintptr(unsafe.Pointer(&process)))
	runtime.KeepAlive(application16)
	runtime.KeepAlive(command16)
	runtime.KeepAlive(work16)
	runtime.KeepAlive(environment)
	runtime.KeepAlive(startup)
	runtime.KeepAlive(imageGuard)
	if r == 0 {
		return nil, nil, fmt.Errorf("CreateProcessW: %w", callErr)
	}
	safety.ProcessCreated = true
	defer syscall.CloseHandle(process.Process)
	defer syscall.CloseHandle(process.Thread)
	r, _, callErr = assignProcessToJobObject.Call(uintptr(job), uintptr(process.Process))
	if r == 0 {
		assignErr := fmt.Errorf("AssignProcessToJobObject: %w", callErr)
		// The suspended process is not in this Job. Terminate and wait on its own
		// process handle; terminating the still-empty Job cannot prove its exit.
		if err := terminateSuspendedProcess(process.Process); err != nil {
			safety.PreserveRuntime = true
			return nil, nil, fmt.Errorf("%v; suspended process exit unconfirmed: %v", assignErr, err)
		}
		safety.JobEmptyConfirmed = true
		return nil, nil, assignErr
	}
	// The process is assigned to the owned Job but its primary thread has never
	// run. Verify the target token directly before allowing any target instruction.
	if err := verifyTargetToken(process.Process, appSID, tokenResult); err != nil {
		return nil, nil, failAfterLaunch(job, safety, fmt.Errorf("suspended target token verification: %w", err))
	}
	r, _, callErr = kernel32.NewProc("ResumeThread").Call(uintptr(process.Thread))
	if r == ^uintptr(0) {
		return nil, nil, failAfterLaunch(job, safety, fmt.Errorf("ResumeThread: %w", callErr))
	}
	wait, _, callErr := kernel32.NewProc("WaitForSingleObject").Call(uintptr(process.Process), uintptr(uint32(timeout/time.Millisecond)))
	if wait == waitTimeout {
		return nil, nil, failAfterLaunch(job, safety, errors.New("owned sandbox Job timed out"))
	}
	if wait != 0 {
		return nil, nil, failAfterLaunch(job, safety, fmt.Errorf("WaitForSingleObject: %w", callErr))
	}
	var exitCode uint32
	r, _, callErr = kernel32.NewProc("GetExitCodeProcess").Call(uintptr(process.Process), uintptr(unsafe.Pointer(&exitCode)))
	if r == 0 {
		return nil, nil, failAfterLaunch(job, safety, fmt.Errorf("GetExitCodeProcess: %w", callErr))
	}
	var active uint32
	// Process signalling and Job Object accounting are not updated in one atomic
	// operation. Allow a short bounded drain, then kill only this owned Job.
	deadline := time.Now().Add(3 * time.Second)
	for {
		active, err = activeProcesses(job)
		if err != nil {
			return &exitCode, nil, failAfterLaunch(job, safety, fmt.Errorf("query Job after target exit: %w", err))
		}
		if active == 0 || time.Now().After(deadline) {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	if active != 0 {
		err := failAfterLaunch(job, safety, errors.New("owned Job still contained child processes"))
		if safety.JobEmptyConfirmed {
			active = 0
		}
		return &exitCode, &active, err
	}
	safety.JobEmptyConfirmed = true
	return &exitCode, &active, nil
}

func probePassed(report *probeEvidence) bool {
	return report != nil && report.AppContainerSIDMatched && len(report.NetworkCapabilitySIDs) == 0 &&
		report.EnvironmentExact && report.OwnFileRoundTrip && report.SentinelReadDenied &&
		report.SentinelWriteDenied && report.LoopbackRefused
}

func runPhase(plan resourcePlan, sourceBinary, expectedSHA string, user *currentUser, recorder *evidenceRecorder) (phase phaseEvidence, returnErr error) {
	// 顶层不再放写死的 CapabilityCount（复核 e：那是启动器常量，不是测量值）。
	phase.Kind = "probe"
	phase.PreserveAll = true
	phase.Resources.RootRelativePath = plan.RootName
	phase.Resources.SentinelRelativePath = plan.SentinelName
	phase.Resources.ProfileName = plan.ProfileName
	root := filepath.Join(plan.CanonicalParent, plan.RootName)
	sentinel := filepath.Join(plan.CanonicalParent, plan.SentinelName)
	var rootOwned, sentinelOwned, profileOwned bool
	var appSID uintptr
	var launchState launchSafety
	defer func() {
		phase.JobEmptyConfirmed = launchState.JobEmptyConfirmed
		phase.RuntimePreserved = true
		phase.Resources.RootOwned = rootOwned
		phase.Resources.SentinelOwned = sentinelOwned
		phase.Resources.ProfileOwned = profileOwned
		switch {
		case launchState.PreserveRuntime:
			phase.JobHandleDisposition = "OS_RECLAIM_ON_RUNNER_EXIT"
			phase.DescendantTermination = "UNKNOWN"
		case launchState.JobEmptyConfirmed:
			phase.JobHandleDisposition = "CLOSED_AFTER_JOB_EMPTY_CONFIRMED"
			phase.DescendantTermination = "JOB_EMPTY_CONFIRMED"
		default:
			phase.JobHandleDisposition = "NOT_APPLICABLE"
			phase.DescendantTermination = "NOT_APPLICABLE"
		}
		if appSID != 0 {
			freeSID.Call(appSID)
		}
	}()

	var profileErr error
	appSID, _, phase.AppContainerSID, profileOwned, profileErr = createProfile(plan.ProfileName)
	// 中间事件必须写「此刻」的归属，而不是 defer 时才能确定的值：否则所有 *-state
	// 事件的 owned 恒为 false，日志本身就在误导复核者。
	phase.Resources.ProfileOwned = profileOwned
	if err := recorder.write("profile-state", phase.Resources); err != nil {
		return phase, err
	}
	if profileErr != nil {
		return phase, profileErr
	}
	rootErr := createDirectoryWithACL(root, user, appSID, "GRGX")
	rootOwned = rootErr == nil
	phase.Resources.RootOwned = rootOwned
	if err := recorder.write("root-state", phase.Resources); err != nil {
		return phase, err
	}
	if rootErr != nil {
		return phase, rootErr
	}
	rootHandle, err := openWindowsFile(root, 0, fileShareRead|fileShareWrite|fileShareDelete, openExisting, fileFlagBackupSemantics, nil)
	if err != nil {
		return phase, err
	}
	defer rootHandle.Close()
	rootIdentity, err := fileIdentityFromHandle(syscall.Handle(rootHandle.Fd()))
	if err != nil {
		return phase, err
	}
	phase.Resources.RootIdentity = &rootIdentity
	if err := recorder.write("root-identity", phase.Resources); err != nil {
		return phase, err
	}

	sentinelFile, sentinelIdentity, sentinelErr := createSentinel(sentinel, "owned isolation sentinel; sandbox must not read or change this file\n", user)
	sentinelOwned = sentinelFile != nil
	phase.Resources.SentinelOwned = sentinelOwned
	if sentinelOwned {
		defer sentinelFile.Close()
		phase.Resources.SentinelIdentity = &sentinelIdentity
	}
	if err := recorder.write("sentinel-state", phase.Resources); err != nil {
		return phase, err
	}
	if sentinelErr != nil {
		return phase, sentinelErr
	}
	// 子目录一律用「带安全描述符的原子创建」：不再 os.Mkdir + 事后 setACL——
	// SetNamedSecurityInfoW 是按路径操作且会用继承 ACE 传播到已存在子树，
	// 在目录内存在 junction 时可能改到沙箱外对象。
	// 注意：标准删除权在 SDDL 里写作 SD（不是 DE）；写错只会在运行时解析失败，
	// 故 main 已在任何持久资源创建之前用 validateDirectoryAclTemplates 先验过一遍。
	for _, spec := range []struct{ name, appRights string }{
		{"bin", "GRGX"},
		{"work", "GRGWGXSD"},
		{"home", "GRGWGXSD"},
		{"tmp", "GRGWGXSD"},
		{"cache", "GRGWGXSD"},
		{"gopath", "GRGWGXSD"},
	} {
		directoryErr := createDirectoryWithACL(filepath.Join(root, spec.name), user, appSID, spec.appRights)
		if err := recorder.write("directory-state", struct {
			Name  string `json:"name"`
			Owned bool   `json:"owned"`
		}{spec.name, directoryErr == nil}); err != nil {
			return phase, err
		}
		if directoryErr != nil {
			return phase, directoryErr
		}
	}
	work := filepath.Join(root, "work")
	workHandle, err := openWindowsFile(work, 0, fileShareRead|fileShareWrite|fileShareDelete, openExisting, fileFlagBackupSemantics, nil)
	if err != nil {
		return phase, err
	}
	workIdentity, err := fileIdentityFromHandle(syscall.Handle(workHandle.Fd()))
	workHandle.Close()
	if err != nil {
		return phase, err
	}
	workDOS, err := dosPath(work)
	if err != nil {
		return phase, err
	}
	workDOSHandle, err := openWindowsFile(workDOS, 0, fileShareRead|fileShareWrite|fileShareDelete, openExisting, fileFlagBackupSemantics, nil)
	if err != nil {
		return phase, err
	}
	workDOSIdentity, err := fileIdentityFromHandle(syscall.Handle(workDOSHandle.Fd()))
	workDOSHandle.Close()
	if err != nil {
		return phase, err
	}
	if workDOSIdentity != workIdentity {
		return phase, errors.New("DOS form of the working directory does not name the created directory")
	}
	executable := filepath.Join(root, "bin", "probe.exe")
	var imageGuard *os.File
	var imageIdentity fileIdentity
	var copyErr error
	phase.BinarySHA256, imageGuard, imageIdentity, copyErr = copyExclusive(sourceBinary, executable, expectedSHA)
	if imageGuard != nil {
		defer imageGuard.Close()
	}
	if err := recorder.write("probe-image", struct {
		SHA256   string       `json:"sha256"`
		Identity fileIdentity `json:"identity"`
	}{phase.BinarySHA256, imageIdentity}); err != nil {
		return phase, err
	}
	if copyErr != nil {
		return phase, copyErr
	}
	executableDOS, err := dosPath(executable)
	if err != nil {
		return phase, err
	}
	imageDOSGuard, err := openWindowsFile(executableDOS, genericRead, fileShareRead, openExisting, fileAttributeNormal, nil)
	if err != nil {
		return phase, err
	}
	imageDOSIdentity, err := fileIdentityFromHandle(syscall.Handle(imageDOSGuard.Fd()))
	imageDOSGuard.Close()
	if err != nil {
		return phase, err
	}
	if imageDOSIdentity != imageIdentity {
		return phase, errors.New("DOS form of the probe image does not name the guarded file")
	}
	environment, environmentKeys, err := environmentBlock(root)
	if err != nil {
		return phase, err
	}
	listener, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		return phase, err
	}
	defer listener.Close()
	if err := recorder.write("prelaunch", struct {
		Root          string       `json:"root"`
		ImageSHA256   string       `json:"imageSha256"`
		ImageIdentity fileIdentity `json:"imageIdentity"`
		WorkIdentity  fileIdentity `json:"workIdentity"`
		LaunchWorkDir string       `json:"launchWorkDir"`
	}{plan.RootName, phase.BinarySHA256, imageIdentity, workIdentity, workDOS}); err != nil {
		return phase, err
	}
	arguments := []string{phase.AppContainerSID, sentinel, listener.Addr().String(), workDOS}
	phase.ProcessExitCode, phase.JobActiveAfterExit, err = launch(executableDOS, workDOS, arguments, environment, appSID, 30*time.Second, &phase.TargetToken, &launchState, imageGuard, &phase.LauncherAsserted)
	phase.ProcessStarted = launchState.ProcessCreated
	phase.JobEmptyConfirmed = launchState.JobEmptyConfirmed
	if err != nil {
		return phase, err
	}
	stdoutPath := filepath.Join(work, "stdout.bin")
	stderrPath := filepath.Join(work, "stderr.bin")
	_, phase.StdoutBytes, err = sha256File(stdoutPath)
	if err != nil {
		return phase, err
	}
	phase.StderrSHA256, phase.StderrBytes, err = sha256File(stderrPath)
	if err != nil {
		return phase, err
	}
	data, err := os.ReadFile(filepath.Join(work, "probe-report.json"))
	if err != nil {
		return phase, err
	}
	var report probeEvidence
	if err := json.Unmarshal(data, &report); err != nil {
		return phase, err
	}
	phase.Probe = &report
	// 启动器自报项集中到 launcherAsserted：证明「我们设置了 HANDLE_LIST / 生成了环境块」，
	// 不证明目标只继承了这三个句柄（未在目标内枚举，见 ISOLATION-REVIEW 未解决项）。
	// 环境块键数优先取探针自己看到的那一份，而不是启动器用占位路径算出来的值（复核 c）。
	envKeys := report.EnvironmentKeys
	if len(envKeys) == 0 {
		envKeys = environmentKeys
	}
	phase.LauncherAsserted.EnvironmentBlockKeys = len(envKeys)
	phase.LauncherAsserted.Note = "launcher self-report; not a measurement of the target"
	if *phase.ProcessExitCode != 0 || *phase.JobActiveAfterExit != 0 || !launchState.JobEmptyConfirmed || !phase.TargetToken.Verified || !probePassed(&report) {
		return phase, errors.New("synthetic probe gates failed; all resources preserved")
	}
	if err := recorder.write("phase-complete", phase); err != nil {
		return phase, err
	}
	return phase, nil
}

const (
	// B5：探针身份必须由 runner 自己钉住，不能由调用方自报。这两个值来自
	// 已审阅的 probe.go 与其在记录的工具链下的 -trimpath 构建；不匹配一律 fail-closed。
	// 刷新条件：改了 probe.go 或用不同工具链/构建参数重建——重算后同时更新两值。
	reviewedProbeSourceSHA256 = "d4d83af0ebb78dc564e8ecafbfe611dff9c1155c2b1496a06960d3792efda022"
	reviewedProbeBinarySHA256 = "7f4ae679a617695f82b019029df3b25c987b04ee597e3c414e991978052a9ace"
)

func main() {
	probeBinary := flag.String("probe", "", "reviewed synthetic probe executable (SHA-256 must equal the compiled-in pin)")
	probeSource := flag.String("probe-source", "probe.go", "reviewed synthetic probe source whose normalized SHA-256 must equal the compiled-in pin")
	parent := flag.String("parent", "", "existing current-change evidence parent")
	evidencePath := flag.String("evidence", "", "new exclusive JSONL evidence path directly beneath parent")
	targetBinary := flag.String("target-binary", "", "rejected in synthetic-probe-only revision")
	targetSHA := flag.String("target-sha256", "", "rejected in synthetic-probe-only revision")
	preserveAll := flag.Bool("synthetic-probe-preserve-all", false, "required: preserve profile, root and sentinel unconditionally")
	flag.Parse()
	report := evidence{
		Schema:    "aifi45.notice-appcontainer-isolation/v4-synthetic-preserve-all-unreviewed",
		StartedAt: time.Now().UTC(),
		Status:    "FAILED",
		Mechanism: "synthetic-only preserve-all; early O_EXCL JSONL; handle-guarded probe image",
	}
	var failure error
	var recorder *evidenceRecorder
	defer func() {
		report.FinishedAt = time.Now().UTC()
		if failure != nil {
			report.Failure = failure.Error()
		}
		if recorder != nil {
			if err := recorder.write("final", report); err != nil {
				fmt.Fprintln(os.Stderr, "append final evidence:", err)
				recorder.file.Close()
				os.Exit(2)
			}
			if err := recorder.file.Close(); err != nil {
				fmt.Fprintln(os.Stderr, "close evidence:", err)
				os.Exit(2)
			}
		}
		if failure != nil {
			fmt.Fprintln(os.Stderr, failure.Error())
			os.Exit(1)
		}
		fmt.Println(report.Status)
	}()
	if *probeBinary == "" || *parent == "" || *evidencePath == "" || flag.NArg() != 0 {
		failure = errors.New("required synthetic probe arguments missing or unexpected positional arguments")
		return
	}
	if !*preserveAll || *targetBinary != "" || *targetSHA != "" {
		failure = errors.New("refused: preserve-all and no target binary are required")
		return
	}
	// B5：不再接受调用方给的 SHA。二进制和源码都必须对上编译期钉住的值，
	// 这样「把任意 exe 连同它自己的哈希传进来」不再能冒充已审探针。
	sourceHash, err := sha256TextFile(*probeSource)
	if err != nil {
		failure = fmt.Errorf("hash probe source: %w", err)
		return
	}
	if !strings.EqualFold(sourceHash, reviewedProbeSourceSHA256) {
		failure = errors.New("probe source does not match the compiled-in reviewed source pin; refusing")
		return
	}
	binaryHash, binarySize, err := sha256File(*probeBinary)
	if err != nil {
		failure = fmt.Errorf("hash probe binary: %w", err)
		return
	}
	if binarySize <= 0 || !strings.EqualFold(binaryHash, reviewedProbeBinarySHA256) {
		failure = errors.New("probe binary does not match the compiled-in reviewed binary pin; refusing")
		return
	}
	report.ProbeSourceSHA256 = sourceHash
	report.ProbeBinarySHA256 = binaryHash
	// 先验 SDDL 模板，再建任何持久资源（顺序本身就是 fail-closed 的一部分）。
	if err := validateDirectoryAclTemplates(); err != nil {
		failure = err
		return
	}
	report.ProbeBinaryBinding = "SOURCE_AND_BINARY_PINNED_IN_RUNNER; PROBE_REPRODUCIBILITY_UNPROVEN"
	report.GoToolchain = "runner-built-with " + runtime.Version() + "; probe-toolchain unverified"
	parentPath, err := filepath.Abs(*parent)
	if err != nil {
		failure = err
		return
	}
	evidenceAbs, err := filepath.Abs(*evidencePath)
	if err != nil {
		failure = err
		return
	}
	relativeEvidence, err := filepath.Rel(parentPath, evidenceAbs)
	if err != nil || relativeEvidence == "." || relativeEvidence == ".." || relativeEvidence != filepath.Base(relativeEvidence) {
		failure = errors.New("evidence must be a new direct child of parent")
		return
	}
	canonical, parentIdentity, err := canonicalParent(parentPath)
	if err != nil {
		failure = err
		return
	}
	report.CanonicalParent = canonical
	report.ParentIdentity = parentIdentity
	plan := resourcePlan{CanonicalParent: canonical, ParentIdentity: parentIdentity}
	if plan.RootName, err = randomName(".ntf-probe-"); err != nil {
		failure = err
		return
	}
	if plan.SentinelName, err = randomName(".ntf-sentinel-"); err != nil {
		failure = err
		return
	}
	if plan.ProfileName, err = randomName("AIFI45.NTF."); err != nil {
		failure = err
		return
	}
	recorder, err = openEvidenceRecorder(evidenceAbs, plan)
	if err != nil {
		failure = err
		return
	}
	report.EvidenceIdentity = recorder.identity
	user, err := getCurrentUser()
	if err != nil {
		failure = err
		return
	}
	_, report.EnvironmentKeys, err = environmentBlock(`C:\placeholder`)
	if err != nil {
		failure = err
		return
	}
	probe, err := runPhase(plan, *probeBinary, reviewedProbeBinarySHA256, user, recorder)
	report.Probe = &probe
	if err != nil {
		failure = fmt.Errorf("probe phase: %w", err)
		return
	}
	report.Status = "SYNTHETIC_PROBE_GATES_PASSED_RESOURCES_PRESERVED"
}
