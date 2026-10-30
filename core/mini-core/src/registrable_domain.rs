use std::net::IpAddr;

pub fn registrable_domain(host: &str) -> Option<&str> {
    let unbracketed = host
        .strip_prefix('[')
        .and_then(|rest| rest.strip_suffix(']'))
        .unwrap_or(host);
    if unbracketed.parse::<IpAddr>().is_ok() {
        return None;
    }
    psl::domain_str(host)
}

#[cfg(test)]
mod tests {
    use super::registrable_domain;

    #[test]
    fn drops_subdomains() {
        assert_eq!(registrable_domain("docs.github.com"), Some("github.com"));
        assert_eq!(registrable_domain("a.b.example.org"), Some("example.org"));
        assert_eq!(registrable_domain("example.com"), Some("example.com"));
    }

    #[test]
    fn multi_label_public_suffixes() {
        assert_eq!(registrable_domain("www.bbc.co.uk"), Some("bbc.co.uk"));
        assert_eq!(registrable_domain("bbc.co.uk"), Some("bbc.co.uk"));
        assert_eq!(
            registrable_domain("a.b.example.com.au"),
            Some("example.com.au")
        );
        assert_eq!(registrable_domain("shop.example.de"), Some("example.de"));
        assert_eq!(
            registrable_domain("city.kawasaki.jp"),
            Some("city.kawasaki.jp")
        );
        assert_eq!(
            registrable_domain("www.city.kawasaki.jp"),
            Some("city.kawasaki.jp")
        );
    }

    #[test]
    fn private_suffixes_count() {
        assert_eq!(registrable_domain("foo.github.io"), Some("foo.github.io"));
        assert_eq!(
            registrable_domain("docs.foo.github.io"),
            Some("foo.github.io")
        );
        assert_eq!(
            registrable_domain("myapp.vercel.app"),
            Some("myapp.vercel.app")
        );
    }

    #[test]
    fn public_suffixes_and_single_labels_have_none() {
        assert_eq!(registrable_domain("github.io"), None);
        assert_eq!(registrable_domain("co.uk"), None);
        assert_eq!(registrable_domain("localhost"), None);
    }

    #[test]
    fn unlisted_top_level_labels_count_as_suffixes() {
        assert_eq!(
            registrable_domain("docs.white.localhost"),
            Some("white.localhost")
        );
        assert_eq!(
            registrable_domain("printer.internal"),
            Some("printer.internal")
        );
    }

    #[test]
    fn ip_addresses_have_none() {
        assert_eq!(registrable_domain("127.0.0.1"), None);
        assert_eq!(registrable_domain("192.168.1.20"), None);
        assert_eq!(registrable_domain("::1"), None);
        assert_eq!(registrable_domain("[2001:db8::1]"), None);
    }

    #[test]
    fn internationalized_names_in_either_form() {
        assert_eq!(
            registrable_domain("www.xn--85x722f.xn--55qx5d.cn"),
            Some("xn--85x722f.xn--55qx5d.cn")
        );
        assert_eq!(registrable_domain("www.食狮.公司.cn"), Some("食狮.公司.cn"));
        assert_eq!(registrable_domain("www.bücher.de"), Some("bücher.de"));
        assert_eq!(
            registrable_domain("www.xn--bcher-kva.de"),
            Some("xn--bcher-kva.de")
        );
    }
}
