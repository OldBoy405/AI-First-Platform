// @vitest-environment jsdom
import { describe, expect, it, vi, beforeEach, afterEach } from "vitest";
import { renderHook } from "@testing-library/react";
import { useLogout } from "./use-logout";
import { SESSION_BARRIER_KEY } from "@multica/core/platform/storage";
import type { ApiClient } from "@multica/core/api";
import type { User } from "@multica/core/types";

vi.mock("../../core/analytics", () => ({ identify: vi.fn(), resetAnalytics: vi.fn() }));
vi.mock("../../core/platform/workspace-storage", () => ({ setCurrentWorkspace: vi.fn() }));

// What client state gets erased, and the order it has to happen in, is pinned
// in core's platform/session-cleanup.test.ts — the session-expiry path runs
// the same function. What is left for this hook is the logout-only tail:
// erase, then drop auth, then move the URL.
const calls = vi.hoisted(() => [] as string[]);
const mockClearClientSessionData = vi.hoisted(() => vi.fn());
const mockAuthLogout = vi.hoisted(() => vi.fn());
const mockPush = vi.hoisted(() => vi.fn());
const queryClient = vi.hoisted(() => ({ id: "query-client" }));

vi.mock("@tanstack/react-query", () => ({
  useQueryClient: () => queryClient,
}));

vi.mock("@multica/core/auth", () => ({
  useAuthStore: Object.assign(
    (selector?: (s: unknown) => unknown) => {
      const state = { logout: mockAuthLogout };
      return selector ? selector(state) : state;
    },
    { getState: () => ({ logout: mockAuthLogout }) },
  ),
}));

vi.mock("@multica/core/platform", () => ({
  clearClientSessionData: mockClearClientSessionData,
}));

vi.mock("@multica/core/paths", () => ({
  paths: { login: () => "/login" },
}));

vi.mock("../navigation", () => ({
  useNavigation: () => ({ push: mockPush }),
}));

describe("useLogout", () => {
  beforeEach(() => {
    vi.stubGlobal("fetch", vi.fn(() => { throw new Error("Unexpected network request"); }));
    calls.length = 0;
    vi.clearAllMocks();
    mockClearClientSessionData.mockImplementation(() => calls.push("clear"));
    mockAuthLogout.mockImplementation(() => calls.push("authLogout"));
    mockPush.mockImplementation(() => calls.push("push"));
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("still records the barrier, invalidates auth and navigates when client session cleanup throws", async () => {
    // The hook's `@multica/core/auth` is mocked below, so the fixture store must come
    // from the real module rather than the mock.
    const { createAuthStore } = await vi.importActual<typeof import("@multica/core/auth")>("@multica/core/auth");
    const data = new Map([[SESSION_BARRIER_KEY, "clean"], ["multica_token", "old-token"]]);
    const api = { setToken: vi.fn() } as unknown as ApiClient;
    const store = createAuthStore({
      api,
      storage: {
        getItem: (key) => data.get(key) ?? null,
        setItem: (key, value) => { data.set(key, value); },
        removeItem: () => { throw new Error("fixture token deletion failure"); },
      },
    });
    store.setState({ user: { id: "old-user" } as User, status: "authenticated", isLoading: false });
    mockAuthLogout.mockImplementation(() => { calls.push("authLogout"); store.getState().logout(); });
    mockClearClientSessionData.mockImplementationOnce(() => {
      calls.push("clear");
      throw new Error("fixture cleanup failure");
    });
    const { result, unmount } = renderHook(() => useLogout());
    try {
      try {
        result.current();
      } catch {
        // Failure reporting is separate from mandatory local auth teardown.
      }
      expect(mockClearClientSessionData).toHaveBeenCalledWith(queryClient);
      expect(mockAuthLogout).toHaveBeenCalledOnce();
      expect(data.get(SESSION_BARRIER_KEY)).toBe("pending");
      expect(data.get("multica_token")).toBe("old-token");
      expect(store.getState()).toMatchObject({ user: null, status: "unauthenticated", sessionBlocked: true });
      expect(api.setToken).toHaveBeenCalledWith(null);
      expect(mockPush).toHaveBeenCalledWith("/login");
      expect(calls).toEqual(["clear", "authLogout", "push"]);
      // Navigation is not proof of persistence erasure or cookie revocation.
    } finally {
      unmount();
    }
  });

  // Erasing after the auth store publishes `unauthenticated` would race the
  // shells' login redirect, and navigating first would leave the caller on a
  // workspace URL that renders null.
  it("erases client state, then drops auth, then navigates to /login", () => {
    const { result } = renderHook(() => useLogout());
    result.current();

    expect(calls).toEqual(["clear", "authLogout", "push"]);
    expect(mockClearClientSessionData).toHaveBeenCalledWith(queryClient);
    expect(mockPush).toHaveBeenCalledWith("/login");
  });
});
