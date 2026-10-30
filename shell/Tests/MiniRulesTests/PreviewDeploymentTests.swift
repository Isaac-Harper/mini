import Testing
import MiniRules

struct PreviewDeploymentTests {
    private static func lastTwoLabels(_ host: String) -> String? {
        let labels = host.split(separator: ".")
        return labels.count >= 2 ? labels.suffix(2).joined(separator: ".") : nil
    }

    @Test func vercelGitBranchPreviewsCarryTheBranch() {
        #expect(PreviewDeployment.of(host: "mini-git-feature-login-isaac.vercel.app")
            == PreviewDeployment(platform: .vercel, project: "mini", branch: "feature-login"))
        #expect(PreviewDeployment.of(host: "my-site-git-main-isaacharpers-projects.vercel.app")
            == PreviewDeployment(platform: .vercel, project: "my-site", branch: "main"))
    }

    @Test func vercelHashPreviewsHaveNoBranch() {
        #expect(PreviewDeployment.of(host: "mini-k3j2h1g9f-isaac.vercel.app") == PreviewDeployment(platform: .vercel, project: "mini", branch: nil))
        #expect(PreviewDeployment.of(host: "next-blog-a1b2c3d4e-vercel.vercel.app") == PreviewDeployment(platform: .vercel, project: "next-blog", branch: nil))
    }

    @Test func vercelProductionIsNotAPreview() {
        #expect(PreviewDeployment.of(host: "mini.vercel.app") == nil)
        #expect(PreviewDeployment.of(host: "my-cool-site.vercel.app") == nil)
        #expect(PreviewDeployment.of(host: "vercel.app") == nil)
        #expect(PreviewDeployment.of(host: "vercel.com") == nil)
    }

    @Test func netlifyDeployPreviewsAndBranchDeploys() {
        #expect(PreviewDeployment.of(host: "deploy-preview-42--mysite.netlify.app") == PreviewDeployment(platform: .netlify, project: "mysite", branch: nil))
        #expect(PreviewDeployment.of(host: "5f8a1b2c3d4e5f6a7b8c9d0e--mysite.netlify.app") == PreviewDeployment(platform: .netlify, project: "mysite", branch: nil))
        #expect(PreviewDeployment.of(host: "staging--mysite.netlify.app") == PreviewDeployment(platform: .netlify, project: "mysite", branch: "staging"))
        #expect(PreviewDeployment.of(host: "mysite.netlify.app") == nil)
    }

    @Test func cloudflarePagesHashAndBranchAliases() {
        #expect(PreviewDeployment.of(host: "1a2b3c4d.blog.pages.dev") == PreviewDeployment(platform: .cloudflarePages, project: "blog", branch: nil))
        #expect(PreviewDeployment.of(host: "dark-mode.blog.pages.dev") == PreviewDeployment(platform: .cloudflarePages, project: "blog", branch: "dark-mode"))
        #expect(PreviewDeployment.of(host: "blog.pages.dev") == nil)
    }

    @Test func otherHostsAreNotPreviews() {
        #expect(PreviewDeployment.of(host: "github.com") == nil)
        #expect(PreviewDeployment.of(host: "localhost") == nil)
        #expect(PreviewDeployment.of(host: "a.b.vercel.app") == nil)
    }

    @Test func productionProjectsComeFromTheFirstLabelAndTheDomain() {
        #expect(PreviewDeployment.productionProjects(ofHost: "mini.vercel.app", registrableDomain: Self.lastTwoLabels) == ["mini"])
        #expect(PreviewDeployment.productionProjects(ofHost: "nextjs.org", registrableDomain: Self.lastTwoLabels) == ["nextjs"])
        #expect(PreviewDeployment.productionProjects(ofHost: "www.nextjs.org", registrableDomain: Self.lastTwoLabels) == ["nextjs"])
        #expect(PreviewDeployment.productionProjects(ofHost: "docs.mini.dev", registrableDomain: Self.lastTwoLabels) == ["docs", "mini"])
        #expect(PreviewDeployment.productionProjects(ofHost: "mini-git-main-isaac.vercel.app", registrableDomain: Self.lastTwoLabels) == [])
        #expect(PreviewDeployment.productionProjects(ofHost: "127.0.0.1", registrableDomain: Self.lastTwoLabels) == [])
        #expect(PreviewDeployment.productionProjects(ofHost: "localhost", registrableDomain: Self.lastTwoLabels) == [])
    }
}
