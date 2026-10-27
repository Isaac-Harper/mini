use cef::*;

use crate::{ad_blocking, client::main_frame_url};

wrap_resource_request_handler! {
    pub struct MiniResourceRequestHandler;

    impl ResourceRequestHandler {
        fn on_before_resource_load(
            &self,
            browser: Option<&mut Browser>,
            _frame: Option<&mut Frame>,
            request: Option<&mut Request>,
            _callback: Option<&mut Callback>,
        ) -> ReturnValue {
            let (Some(browser), Some(request)) = (browser, request) else {
                return ReturnValue::CONTINUE;
            };
            let url = CefString::from(&request.url()).to_string();
            let top_level_url = main_frame_url(browser);
            if ad_blocking::should_cancel(&url, &top_level_url, request.resource_type()) {
                ReturnValue::CANCEL
            } else {
                ReturnValue::CONTINUE
            }
        }
    }
}
