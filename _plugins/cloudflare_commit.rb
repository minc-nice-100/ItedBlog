module Jekyll
  class CloudflareCommit < Jekyll::Generator
    priority :highest
    def generate(site)
      # Cloudflare Pages 注入的环境变量
      commit = ENV['CF_PAGES_COMMIT_SHA'] || `git rev-parse HEAD`.strip rescue 'unknown'
      site.config['commit_hash'] = commit
      site.config['commit_short'] = commit[0,7]
      site.config['branch'] = ENV['CF_PAGES_BRANCH'] || 'unknown'
    end
  end
end