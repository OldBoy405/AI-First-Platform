// AIFIRST: trusted T committed verdict channel — daemon → server control client (M003, S6).
//
// 重发必须逐字节原样。任何「解成结构体再编码」都会改键序、空白与转义，
// 让同一份证明在上游看起来是另一份。
package daemon

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net/http"
)

// ControlVerdictPath 是 daemon 提交裁决 envelope 的固定路径。
const ControlVerdictPath = "/api/daemon/execution-control/verdict"

// PostControlVerdictBytes 把 raw 原样作为请求体发出，并把响应体原样返回。
// 响应体不重新编码：重放时服务端会把首次的字节还回来，客户端要能原样交出去。
func (c *Client) PostControlVerdictBytes(ctx context.Context, raw []byte) ([]byte, error) {
	if len(raw) == 0 {
		return nil, fmt.Errorf("control verdict: 空 envelope")
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL+ControlVerdictPath, bytes.NewReader(raw))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	c.setWorkspaceHeader(req, ctx)
	c.setIdentityHeaders(req)
	if token := c.Token(); token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	resp, err := c.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return body, &requestError{Method: http.MethodPost, Path: ControlVerdictPath, StatusCode: resp.StatusCode, Body: string(body)}
	}
	return body, nil
}
