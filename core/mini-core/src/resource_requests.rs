use cef::*;

use crate::{MiniTabId, ad_blocking, client::main_frame_url, page_health, response_headers};

wrap_resource_request_handler! {
    pub struct MiniResourceRequestHandler {
        tab: MiniTabId,
        blocks_ads: bool,
        health_page: u64,
    }

    impl ResourceRequestHandler {
        fn on_before_resource_load(
            &self,
            browser: Option<&mut Browser>,
            _frame: Option<&mut Frame>,
            request: Option<&mut Request>,
            _callback: Option<&mut Callback>,
        ) -> ReturnValue {
            let (true, Some(browser), Some(request)) = (self.blocks_ads, browser, request) else {
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

        fn on_resource_response(
            &self,
            _browser: Option<&mut Browser>,
            frame: Option<&mut Frame>,
            request: Option<&mut Request>,
            response: Option<&mut Response>,
        ) -> ::std::os::raw::c_int {
            let is_main_frame_document = frame.is_some_and(|frame| frame.is_main() == 1)
                && request.is_some_and(|request| request.resource_type() == ResourceType::MAIN_FRAME);
            if let (true, Some(response)) = (is_main_frame_document, response) {
                response_headers::report_from_io_thread(self.tab, response);
            }
            0
        }

        fn on_resource_load_complete(
            &self,
            _browser: Option<&mut Browser>,
            _frame: Option<&mut Frame>,
            request: Option<&mut Request>,
            response: Option<&mut Response>,
            status: UrlrequestStatus,
            _received_content_length: i64,
        ) {
            if let (true, Some(request)) = (self.health_page != 0, request) {
                page_health::report_from_io_thread(self.tab, self.health_page, request, response.as_deref(), status);
            }
        }
    }
}
