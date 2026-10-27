use cef::*;
use std::{cell::RefCell, collections::HashMap};

use crate::{
    MiniTabId,
    state::{c_string, callbacks, next_request_id},
};

pub const CAMERA: u32 = 1 << 0;
pub const MICROPHONE: u32 = 1 << 1;
pub const SCREEN_CAPTURE: u32 = 1 << 2;
pub const GEOLOCATION: u32 = 1 << 3;
pub const NOTIFICATIONS: u32 = 1 << 4;
pub const CLIPBOARD: u32 = 1 << 5;
pub const MIDI: u32 = 1 << 6;
pub const STORAGE: u32 = 1 << 7;
pub const WINDOW_MANAGEMENT: u32 = 1 << 8;
pub const LOCAL_NETWORK: u32 = 1 << 9;
pub const OTHER: u32 = 1 << 31;

use sys::cef_media_access_permission_types_t as media;
use sys::cef_permission_request_types_t as prompt;

const MEDIA_BITS: [(u32, u32); 4] = [
    (
        media::CEF_MEDIA_PERMISSION_DEVICE_AUDIO_CAPTURE as u32,
        MICROPHONE,
    ),
    (
        media::CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE as u32,
        CAMERA,
    ),
    (
        media::CEF_MEDIA_PERMISSION_DESKTOP_AUDIO_CAPTURE as u32,
        SCREEN_CAPTURE,
    ),
    (
        media::CEF_MEDIA_PERMISSION_DESKTOP_VIDEO_CAPTURE as u32,
        SCREEN_CAPTURE,
    ),
];

const PROMPT_BITS: [(u32, u32); 12] = [
    (prompt::CEF_PERMISSION_TYPE_CAMERA_STREAM as u32, CAMERA),
    (prompt::CEF_PERMISSION_TYPE_MIC_STREAM as u32, MICROPHONE),
    (prompt::CEF_PERMISSION_TYPE_GEOLOCATION as u32, GEOLOCATION),
    (
        prompt::CEF_PERMISSION_TYPE_NOTIFICATIONS as u32,
        NOTIFICATIONS,
    ),
    (prompt::CEF_PERMISSION_TYPE_CLIPBOARD as u32, CLIPBOARD),
    (prompt::CEF_PERMISSION_TYPE_MIDI_SYSEX as u32, MIDI),
    (prompt::CEF_PERMISSION_TYPE_STORAGE_ACCESS as u32, STORAGE),
    (
        prompt::CEF_PERMISSION_TYPE_TOP_LEVEL_STORAGE_ACCESS as u32,
        STORAGE,
    ),
    (
        prompt::CEF_PERMISSION_TYPE_WINDOW_MANAGEMENT as u32,
        WINDOW_MANAGEMENT,
    ),
    (
        prompt::CEF_PERMISSION_TYPE_LOCAL_NETWORK as u32,
        LOCAL_NETWORK,
    ),
    (
        prompt::CEF_PERMISSION_TYPE_LOCAL_NETWORK_ACCESS_DEPRECATED as u32,
        LOCAL_NETWORK,
    ),
    (
        prompt::CEF_PERMISSION_TYPE_LOOPBACK_NETWORK as u32,
        LOCAL_NETWORK,
    ),
];

pub fn media_to_mini(media_bits: u32) -> u32 {
    MEDIA_BITS
        .iter()
        .filter(|(media_bit, _)| media_bits & media_bit != 0)
        .fold(0, |mini, (_, mini_bit)| mini | mini_bit)
}

pub fn granted_media(requested_media: u32, granted_mini: u32) -> u32 {
    MEDIA_BITS
        .iter()
        .filter(|(media_bit, mini_bit)| {
            requested_media & media_bit != 0 && granted_mini & mini_bit != 0
        })
        .fold(0, |media_bits, (media_bit, _)| media_bits | media_bit)
}

pub fn prompt_to_mini(prompt_bits: u32) -> u32 {
    let known = PROMPT_BITS
        .iter()
        .fold(0, |known, (prompt_bit, _)| known | prompt_bit);
    let mapped = PROMPT_BITS
        .iter()
        .filter(|(prompt_bit, _)| prompt_bits & prompt_bit != 0)
        .fold(0, |mini, (_, mini_bit)| mini | mini_bit);
    if prompt_bits & !known != 0 {
        mapped | OTHER
    } else {
        mapped
    }
}

enum PendingCallback {
    Media {
        callback: MediaAccessCallback,
        requested_media: u32,
    },
    Prompt {
        callback: PermissionPromptCallback,
        prompt_id: u64,
        requested_mini: u32,
    },
}

struct PendingPermission {
    tab: MiniTabId,
    callback: PendingCallback,
}

thread_local! {
    static PENDING: RefCell<HashMap<u64, PendingPermission>> = RefCell::new(HashMap::new());
}

fn request(tab: MiniTabId, origin: &str, permissions: u32, callback: PendingCallback) {
    let request = next_request_id();
    PENDING.with_borrow_mut(|pending| pending.insert(request, PendingPermission { tab, callback }));
    let origin = c_string(origin);
    unsafe { (callbacks().permission_requested)(tab, request, origin.as_ptr(), permissions) };
}

pub fn request_media(
    tab: MiniTabId,
    origin: &str,
    requested_media: u32,
    callback: MediaAccessCallback,
) {
    let permissions = media_to_mini(requested_media);
    request(
        tab,
        origin,
        permissions,
        PendingCallback::Media {
            callback,
            requested_media,
        },
    );
}

pub fn request_prompt(
    tab: MiniTabId,
    origin: &str,
    prompt_id: u64,
    requested_prompt: u32,
    callback: PermissionPromptCallback,
) {
    let requested_mini = prompt_to_mini(requested_prompt);
    request(
        tab,
        origin,
        requested_mini,
        PendingCallback::Prompt {
            callback,
            prompt_id,
            requested_mini,
        },
    );
}

pub fn respond(request: u64, granted: u32) {
    let Some(pending) = PENDING.with_borrow_mut(|pending| pending.remove(&request)) else {
        return;
    };
    match pending.callback {
        PendingCallback::Media {
            callback,
            requested_media,
        } => {
            callback.cont(granted_media(requested_media, granted));
        }
        PendingCallback::Prompt {
            callback,
            requested_mini,
            ..
        } => {
            let result = if requested_mini & granted == requested_mini {
                PermissionRequestResult::ACCEPT
            } else {
                PermissionRequestResult::DENY
            };
            callback.cont(result);
        }
    }
}

pub fn prompt_dismissed(prompt_id: u64) {
    let request = PENDING.with_borrow_mut(|pending| {
        let request = pending
            .iter()
            .find_map(|(request, entry)| match entry.callback {
                PendingCallback::Prompt {
                    prompt_id: pending_prompt,
                    ..
                } if pending_prompt == prompt_id => Some(*request),
                _ => None,
            })?;
        pending.remove(&request);
        Some(request)
    });
    if let Some(request) = request {
        unsafe { (callbacks().permission_dismissed)(request) };
    }
}

pub fn dismiss_for_tab(tab: MiniTabId) {
    let dismissed: Vec<(u64, PendingPermission)> = PENDING.with_borrow_mut(|pending| {
        let requests: Vec<u64> = pending
            .iter()
            .filter(|(_, entry)| entry.tab == tab)
            .map(|(request, _)| *request)
            .collect();
        requests
            .into_iter()
            .map(|request| {
                (
                    request,
                    pending.remove(&request).expect("request listed above"),
                )
            })
            .collect()
    });
    for (request, entry) in dismissed {
        if let PendingCallback::Media { callback, .. } = entry.callback {
            callback.cancel();
        }
        unsafe { (callbacks().permission_dismissed)(request) };
    }
}

fn normalized_origin(origin: Option<&CefString>) -> String {
    let origin = origin.map(CefString::to_string).unwrap_or_default();
    match url::Url::parse(&origin) {
        Ok(parsed) if parsed.origin().is_tuple() => parsed.origin().ascii_serialization(),
        _ => origin,
    }
}

wrap_permission_handler! {
    pub struct MiniPermissionHandler {
        tab: MiniTabId,
    }

    impl PermissionHandler {
        fn on_request_media_access_permission(
            &self,
            _browser: Option<&mut Browser>,
            _frame: Option<&mut Frame>,
            requesting_origin: Option<&CefString>,
            requested_permissions: u32,
            callback: Option<&mut MediaAccessCallback>,
        ) -> ::std::os::raw::c_int {
            let callback = callback.expect("media access request without a callback").clone();
            request_media(self.tab, &normalized_origin(requesting_origin), requested_permissions, callback);
            1
        }

        fn on_show_permission_prompt(
            &self,
            _browser: Option<&mut Browser>,
            prompt_id: u64,
            requesting_origin: Option<&CefString>,
            requested_permissions: u32,
            callback: Option<&mut PermissionPromptCallback>,
        ) -> ::std::os::raw::c_int {
            let callback = callback.expect("permission prompt without a callback").clone();
            request_prompt(self.tab, &normalized_origin(requesting_origin), prompt_id, requested_permissions, callback);
            1
        }

        fn on_dismiss_permission_prompt(
            &self,
            _browser: Option<&mut Browser>,
            prompt_id: u64,
            _result: PermissionRequestResult,
        ) {
            prompt_dismissed(prompt_id);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn maps_media_bits_both_ways_limited_to_requested() {
        let audio = media::CEF_MEDIA_PERMISSION_DEVICE_AUDIO_CAPTURE as u32;
        let video = media::CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE as u32;
        let desktop_video = media::CEF_MEDIA_PERMISSION_DESKTOP_VIDEO_CAPTURE as u32;
        assert_eq!(media_to_mini(audio | video), MICROPHONE | CAMERA);
        assert_eq!(media_to_mini(desktop_video), SCREEN_CAPTURE);
        assert_eq!(granted_media(audio | video, CAMERA | SCREEN_CAPTURE), video);
        assert_eq!(granted_media(audio, CAMERA | MICROPHONE), audio);
        assert_eq!(granted_media(audio | video, 0), 0);
    }

    #[test]
    fn maps_prompt_bits_with_unknown_as_other() {
        let geolocation = prompt::CEF_PERMISSION_TYPE_GEOLOCATION as u32;
        let storage = prompt::CEF_PERMISSION_TYPE_TOP_LEVEL_STORAGE_ACCESS as u32;
        let ar_session = prompt::CEF_PERMISSION_TYPE_AR_SESSION as u32;
        assert_eq!(prompt_to_mini(geolocation | storage), GEOLOCATION | STORAGE);
        assert_eq!(prompt_to_mini(ar_session), OTHER);
        assert_eq!(
            prompt_to_mini(geolocation | ar_session),
            GEOLOCATION | OTHER
        );
    }
}
