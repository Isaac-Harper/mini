use cef::*;

use crate::{
    MiniTabId,
    state::{c_string, callbacks, tab_is_live},
};

const REPORTED_HEADERS: [&str; 8] = [
    "server",
    "age",
    "x-vercel-cache",
    "x-vercel-id",
    "cf-cache-status",
    "cf-ray",
    "x-nextjs-cache",
    "x-nextjs-prerender",
];

pub fn report_from_io_thread(tab: MiniTabId, response: &Response) {
    let lines: String = REPORTED_HEADERS
        .iter()
        .filter_map(|name| {
            let value = CefString::from(&response.header_by_name(Some(&CefString::from(*name))))
                .to_string();
            let value = value.trim();
            (!value.is_empty() && !value.contains('\n')).then(|| format!("{name}: {value}\n"))
        })
        .collect();
    let mut task = HeadersReport::new(tab, lines);
    assert_eq!(
        post_task(ThreadId::UI, Some(&mut task)),
        1,
        "cannot post response headers to the UI thread"
    );
}

wrap_task! {
    struct HeadersReport {
        tab: MiniTabId,
        lines: String,
    }

    impl Task {
        fn execute(&self) {
            if !tab_is_live(self.tab) {
                return;
            }
            let lines = c_string(&self.lines);
            unsafe { (callbacks().main_frame_headers_received)(self.tab, lines.as_ptr()) };
        }
    }
}
