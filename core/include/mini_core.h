#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// The shell (Swift) owns tab identity. Zero is never a valid tab id.
typedef uint64_t MiniTabId;

// Where a popup (window.open, target=_blank with opener) should live.
// Return tab = 0 to block the popup.
typedef struct MiniPopupTarget {
  MiniTabId tab;
  void *parent_view;  // NSView * the popup browser is created inside
} MiniPopupTarget;

typedef enum MiniPermission {
  MINI_PERMISSION_CAMERA = 1 << 0,
  MINI_PERMISSION_MICROPHONE = 1 << 1,
  MINI_PERMISSION_SCREEN_CAPTURE = 1 << 2,
  MINI_PERMISSION_GEOLOCATION = 1 << 3,
  MINI_PERMISSION_NOTIFICATIONS = 1 << 4,
  MINI_PERMISSION_CLIPBOARD = 1 << 5,
  MINI_PERMISSION_MIDI = 1 << 6,
  MINI_PERMISSION_STORAGE = 1 << 7,
  MINI_PERMISSION_WINDOW_MANAGEMENT = 1 << 8,
  MINI_PERMISSION_LOCAL_NETWORK = 1 << 9,
  MINI_PERMISSION_OTHER = 1u << 31,
} MiniPermission;

typedef enum MiniRenderTermination {
  MINI_RENDER_ABNORMAL = 0,
  MINI_RENDER_KILLED = 1,
  MINI_RENDER_CRASHED = 2,
  MINI_RENDER_OUT_OF_MEMORY = 3,
  MINI_RENDER_LAUNCH_FAILED = 4,
  MINI_RENDER_INTEGRITY_FAILURE = 5,
} MiniRenderTermination;

// Every callback is invoked on the main thread. Strings are UTF-8 and only
// valid for the duration of the call.
typedef struct MiniCallbacks {
  void (*address_changed)(MiniTabId tab, const char *url);
  void (*title_changed)(MiniTabId tab, const char *title);
  // PNG bytes at 2x scale, downloaded by Chromium. length 0 means no favicon.
  void (*favicon_changed)(MiniTabId tab, const uint8_t *png, size_t length);
  void (*loading_state_changed)(MiniTabId tab, bool is_loading, bool can_go_back, bool can_go_forward);
  // Link opened into a new tab without an opener (cmd-click, middle-click).
  void (*open_tab_requested)(MiniTabId opener, const char *url, bool foreground);
  // Popup that keeps its opener (OAuth flows). Synchronous: the shell creates
  // the tab and its host view before returning.
  MiniPopupTarget (*popup_requested)(MiniTabId opener, const char *url);
  // Raw key-down with Command or Control held, before the page sees it.
  // ns_event is an NSEvent *. Return true when the shell consumed it.
  bool (*pre_key_event)(MiniTabId tab, void *ns_event);
  // The page or navigation wants keyboard focus. Return false to refuse.
  bool (*focus_requested)(MiniTabId tab);
  void (*web_got_focus)(MiniTabId tab);
  // Download progress, fired on every update. total_bytes is -1 when unknown.
  // The last report for a download has is_complete or is_canceled set.
  void (*download_updated)(uint32_t download, const char *file_name, const char *path, int64_t received_bytes,
                           int64_t total_bytes, bool is_complete, bool is_canceled);
  // A site asks for one or more MiniPermission bits. Answer later with
  // mini_permission_respond(request, granted bits). permission_dismissed
  // means the request went away (navigation, tab closed) unanswered.
  void (*permission_requested)(MiniTabId tab, uint64_t request, const char *origin, uint32_t permissions);
  void (*permission_dismissed)(uint64_t request);
  // HTTP authentication (basic/digest, proxy). Answer later with
  // mini_auth_respond.
  void (*auth_requested)(MiniTabId tab, uint64_t request, const char *host, const char *realm, bool is_proxy);
  // A login form was found in a frame in response to mini_request_login_fill
  // (never from mere focus). frame_origin comes from the browser side (the
  // frame's committed URL), never from page script.
  void (*login_field_focused)(MiniTabId tab, const char *frame_id, const char *frame_origin);
  // The tab's renderer process is gone (crash, kill, out of memory).
  // reason is a MiniRenderTermination.
  void (*render_process_terminated)(MiniTabId tab, int32_t reason);
  // Whether any frame of the tab currently shows a password field. Fires only
  // on changes; a main-frame navigation resets it to false.
  void (*login_form_presence_changed)(MiniTabId tab, bool has_login_form);
  // Web Notifications from the page shim. Only sent while the frame's origin
  // is granted through mini_set_notification_permission. notification is
  // unique per frame; strings are UTF-8 and only valid during the call.
  void (*notification_show)(MiniTabId tab, const char *frame_id, uint32_t notification, const char *origin,
                            const char *title, const char *body, const char *tag, bool silent);
  void (*notification_close)(MiniTabId tab, const char *frame_id, uint32_t notification);
  // Whether any media element in the tab is audibly playing, with the page's
  // mediaSession title (and artist) when it sets one, else "". Fires on changes.
  void (*audio_state_changed)(MiniTabId tab, bool is_playing, const char *media_title);
  void (*browser_closed)(MiniTabId tab);
  void (*all_browsers_closed)(void);
} MiniCallbacks;

// Browser process lifecycle. NSApp must already be an NSApplication subclass
// implementing CefAppProtocol before mini_initialize is called.
// filter_lists_path: directory where ad block lists are cached and refreshed.
bool mini_initialize(int argc, char **argv, const char *root_cache_path, const char *filter_lists_path,
                     MiniCallbacks callbacks);
void mini_run_message_loop(void);
void mini_quit_message_loop(void);
void mini_shutdown(void);

// Browser creation is asynchronous. Calls for a tab whose browser is not
// created yet are applied once it is (latest url wins, focus/hidden replayed).
void mini_browser_create(MiniTabId tab, void *parent_view, const char *url);
void mini_browser_load_url(MiniTabId tab, const char *url);
void mini_browser_go_back(MiniTabId tab);
void mini_browser_go_forward(MiniTabId tab);
void mini_browser_reload(MiniTabId tab);
void mini_browser_stop(MiniTabId tab);
void mini_browser_set_focus(MiniTabId tab, bool focused);
void mini_browser_set_hidden(MiniTabId tab, bool hidden);
// direction: -1 zoom out, 0 reset, +1 zoom in. Returns the new zoom level
// (CEF units: factor = 1.2^level; 0 is 100%), or 0 without a browser.
double mini_browser_zoom(MiniTabId tab, int direction);
void mini_browser_set_zoom_level(MiniTabId tab, double level);
void mini_browser_find(MiniTabId tab, const char *text, bool forward, bool find_next);
void mini_browser_stop_finding(MiniTabId tab);
void mini_browser_show_dev_tools(MiniTabId tab);
void mini_browser_close(MiniTabId tab);
// Force-closes every browser. all_browsers_closed fires when none remain
// (immediately if none exist).
void mini_close_all_browsers(void);

// Cancels an in-progress download reported by download_updated. No-op once
// it has completed or been canceled.
void mini_download_cancel(uint32_t download);

// Notification permission the page shim reports for an origin
// (scheme://host[:port]). Applies to frames that load afterwards; a pending
// Notification.requestPermission resolves through mini_permission_respond.
typedef enum MiniNotificationPermission {
  MINI_NOTIFICATION_DEFAULT = 0,
  MINI_NOTIFICATION_GRANTED = 1,
  MINI_NOTIFICATION_DENIED = 2,
} MiniNotificationPermission;
void mini_browser_set_muted(MiniTabId tab, bool muted);
// Pauses audible media elements in every frame (play = false) or resumes the
// ones it paused, else the last paused element (play = true).
void mini_browser_control_media(MiniTabId tab, bool play);

void mini_set_notification_permission(const char *origin, int32_t state);
// Fires the page's click event for a notification the user clicked.
void mini_notification_clicked(MiniTabId tab, const char *frame_id, uint32_t notification);

// granted is a MiniPermission bitmask; 0 denies everything requested.
void mini_permission_respond(uint64_t request, uint32_t granted);
// username NULL cancels.
void mini_auth_respond(uint64_t request, const char *username, const char *password);

// Looks for a login form in every frame of the tab; login_field_focused
// fires for the first frame that has one.
void mini_request_login_fill(MiniTabId tab);
// Fills the login form last reported by frame_id. No-op if that frame is gone
// or navigated to another origin than expected_origin.
void mini_fill_login(MiniTabId tab, const char *frame_id, const char *expected_origin, const char *username,
                     const char *password);

// Ad blocking is on by default. Exempt hosts (exact host match, e.g.
// "www.example.com") get neither network nor cosmetic filtering.
void mini_adblock_set_enabled(bool enabled);
void mini_adblock_set_host_exempt(const char *host, bool exempt);

#ifdef __cplusplus
}
#endif
