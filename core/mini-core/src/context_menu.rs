use cef::*;
use std::ffi::{CString, c_char};

use crate::{
    MiniTabId,
    state::{c_string, callbacks},
};

pub const FLAG_LINK: u32 = 1 << 0;
pub const FLAG_IMAGE: u32 = 1 << 1;
pub const FLAG_SELECTION: u32 = 1 << 2;
pub const FLAG_EDITABLE: u32 = 1 << 3;

const COMMAND_UNDO: i32 = 0;
const COMMAND_REDO: i32 = 1;
const COMMAND_CUT: i32 = 2;
const COMMAND_COPY: i32 = 3;
const COMMAND_PASTE: i32 = 4;
const COMMAND_DELETE: i32 = 5;
const COMMAND_SELECT_ALL: i32 = 6;
const MAXIMUM_SUGGESTIONS: usize = 5;

#[repr(C)]
pub struct MiniContextMenu {
    pub flags: u32,
    pub edit_capabilities: u32,
    pub x: i32,
    pub y: i32,
    pub link_url: *const c_char,
    pub image_url: *const c_char,
    pub selection_text: *const c_char,
    pub misspelled_word: *const c_char,
    pub suggestions: *const *const c_char,
    pub suggestion_count: usize,
}

fn userfree_text(value: CefStringUserfree) -> String {
    CefString::from(&value).to_string()
}

fn edit_capabilities(params: &ContextMenuParams) -> u32 {
    let flags = params.edit_state_flags().as_ref().0;
    let mapping = [
        (sys::cef_context_menu_edit_state_flags_t::CM_EDITFLAG_CAN_UNDO.0, 1 << 0),
        (sys::cef_context_menu_edit_state_flags_t::CM_EDITFLAG_CAN_REDO.0, 1 << 1),
        (sys::cef_context_menu_edit_state_flags_t::CM_EDITFLAG_CAN_CUT.0, 1 << 2),
        (sys::cef_context_menu_edit_state_flags_t::CM_EDITFLAG_CAN_COPY.0, 1 << 3),
        (sys::cef_context_menu_edit_state_flags_t::CM_EDITFLAG_CAN_PASTE.0, 1 << 4),
        (sys::cef_context_menu_edit_state_flags_t::CM_EDITFLAG_CAN_DELETE.0, 1 << 5),
        (sys::cef_context_menu_edit_state_flags_t::CM_EDITFLAG_CAN_SELECT_ALL.0, 1 << 6),
    ];
    mapping
        .iter()
        .filter(|(cef_flag, _)| flags & cef_flag != 0)
        .fold(0, |capabilities, (_, mini_flag)| capabilities | mini_flag)
}

fn menu_flags(params: &ContextMenuParams) -> u32 {
    let type_flags = params.type_flags().as_ref().0;
    let mut flags = 0;
    if type_flags & sys::cef_context_menu_type_flags_t::CM_TYPEFLAG_LINK.0 != 0 {
        flags |= FLAG_LINK;
    }
    if *params.media_type().as_ref() == sys::cef_context_menu_media_type_t::CM_MEDIATYPE_IMAGE {
        flags |= FLAG_IMAGE;
    }
    if type_flags & sys::cef_context_menu_type_flags_t::CM_TYPEFLAG_SELECTION.0 != 0 {
        flags |= FLAG_SELECTION;
    }
    if params.is_editable() == 1 {
        flags |= FLAG_EDITABLE;
    }
    flags
}

pub fn request(tab: MiniTabId, params: &ContextMenuParams) {
    let flags = menu_flags(params);
    let link_url = c_string(&userfree_text(params.link_url()));
    let image_url = c_string(&if flags & FLAG_IMAGE != 0 { userfree_text(params.source_url()) } else { String::new() });
    let selection_text = c_string(&userfree_text(params.selection_text()));
    let misspelled_word = c_string(&userfree_text(params.misspelled_word()));
    let mut suggestion_list = CefStringList::new();
    params.dictionary_suggestions(Some(&mut suggestion_list));
    let suggestions: Vec<CString> = suggestion_list
        .into_iter()
        .take(MAXIMUM_SUGGESTIONS)
        .map(|suggestion| c_string(&suggestion))
        .collect();
    let suggestion_pointers: Vec<*const c_char> = suggestions.iter().map(|suggestion| suggestion.as_ptr()).collect();
    let menu = MiniContextMenu {
        flags,
        edit_capabilities: edit_capabilities(params),
        x: params.xcoord(),
        y: params.ycoord(),
        link_url: link_url.as_ptr(),
        image_url: image_url.as_ptr(),
        selection_text: selection_text.as_ptr(),
        misspelled_word: misspelled_word.as_ptr(),
        suggestions: suggestion_pointers.as_ptr(),
        suggestion_count: suggestion_pointers.len(),
    };
    unsafe { (callbacks().context_menu_requested)(tab, &menu) };
}

pub fn perform_edit(browser: &Browser, command: i32) {
    let frame = browser.focused_frame().or_else(|| browser.main_frame()).expect("browser has no frame");
    match command {
        COMMAND_UNDO => frame.undo(),
        COMMAND_REDO => frame.redo(),
        COMMAND_CUT => frame.cut(),
        COMMAND_COPY => frame.copy(),
        COMMAND_PASTE => frame.paste(),
        COMMAND_DELETE => frame.del(),
        COMMAND_SELECT_ALL => frame.select_all(),
        other => panic!("unknown edit command {other}"),
    }
}

wrap_context_menu_handler! {
    pub struct MiniContextMenuHandler {
        tab: MiniTabId,
    }

    impl ContextMenuHandler {
        fn run_context_menu(
            &self,
            _browser: Option<&mut Browser>,
            _frame: Option<&mut Frame>,
            params: Option<&mut ContextMenuParams>,
            _model: Option<&mut MenuModel>,
            callback: Option<&mut RunContextMenuCallback>,
        ) -> ::std::os::raw::c_int {
            let params = params.expect("context menu without params");
            request(self.tab, params);
            callback.expect("context menu without a callback").cancel();
            1
        }
    }
}
