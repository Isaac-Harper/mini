use cef::*;
use std::ffi::{CString, c_char};

use crate::state::{c_string, callbacks};

wrap_app! {
    pub struct MiniApp;

    impl App {
        fn browser_process_handler(&self) -> Option<BrowserProcessHandler> {
            Some(MiniBrowserProcessHandler::new())
        }
    }
}

wrap_browser_process_handler! {
    struct MiniBrowserProcessHandler;

    impl BrowserProcessHandler {
        fn on_already_running_app_relaunch(
            &self,
            command_line: Option<&mut CommandLine>,
            _current_directory: Option<&CefString>,
        ) -> ::std::os::raw::c_int {
            let mut argument_list = CefStringList::new();
            command_line
                .expect("relaunch without a command line")
                .arguments(Some(&mut argument_list));
            let arguments: Vec<CString> = argument_list.into_iter().map(|argument| c_string(&argument)).collect();
            let pointers: Vec<*const c_char> = arguments.iter().map(|argument| argument.as_ptr()).collect();
            unsafe { (callbacks().app_relaunched)(pointers.as_ptr(), pointers.len()) };
            1
        }
    }
}
