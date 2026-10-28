use cef::*;
use std::{
    cell::RefCell,
    ffi::{c_char, c_void},
};

use crate::state::c_string;

pub type EntryVisitor = unsafe extern "C" fn(*mut c_void, i32, bool, *const c_char, *const c_char);

struct Entry {
    is_current: bool,
    url: String,
    title: String,
}

wrap_navigation_entry_visitor! {
    struct EntryCollector {
        entries: std::rc::Rc<RefCell<Vec<Entry>>>,
    }

    impl NavigationEntryVisitor {
        fn visit(
            &self,
            entry: Option<&mut NavigationEntry>,
            current: ::std::os::raw::c_int,
            _index: ::std::os::raw::c_int,
            _total: ::std::os::raw::c_int,
        ) -> ::std::os::raw::c_int {
            let entry = entry.expect("navigation entry visit without an entry");
            self.entries.borrow_mut().push(Entry {
                is_current: current != 0,
                url: CefString::from(&entry.url()).to_string(),
                title: CefString::from(&entry.title()).to_string(),
            });
            1
        }
    }
}

pub fn visit_entries(browser: &Browser, visitor: EntryVisitor, context: *mut c_void) {
    let entries = std::rc::Rc::new(RefCell::new(Vec::new()));
    let mut collector = EntryCollector::new(entries.clone());
    browser
        .host()
        .expect("browser has no host")
        .navigation_entries(Some(&mut collector), 0);
    for (index, entry) in entries.take().into_iter().enumerate() {
        let url = c_string(&entry.url);
        let title = c_string(&entry.title);
        let index = i32::try_from(index).expect("navigation history longer than i32");
        unsafe { visitor(context, index, entry.is_current, url.as_ptr(), title.as_ptr()) };
    }
}

pub fn go_to_offset(browser: &Browser, offset: i32) {
    let frame = browser.main_frame().expect("browser has no main frame");
    let script = format!("history.go({offset})");
    let frame_url = CefString::from(&frame.url()).to_string();
    frame.execute_java_script(Some(&CefString::from(script.as_str())), Some(&CefString::from(frame_url.as_str())), 0);
}
