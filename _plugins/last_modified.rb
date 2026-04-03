# _plugins/last_modified.rb
module Jekyll
  class LastModifiedTag < Liquid::Tag
    def render(context)
      page = context.environments.first['page']
      file_path = page['path']
      
      # 获取文件的最后提交时间戳
      get_last_commit_timestamp(file_path)
    end

    private

    def get_last_commit_timestamp(file_path)
      begin
        # 用 git log 获取 Unix 时间戳
        cmd = "git log -1 --format=%ct -- #{file_path}"
        `#{cmd}`.strip
      rescue
        # 失败返回空字符串
        ""
      end
    end
  end

  class SiteLastModifiedTag < Liquid::Tag
    def render(context)
      begin
        # 获取整个站点的最后提交时间戳
        cmd = "git log -1 --format=%ct"
        `#{cmd}`.strip
      rescue
        ""
      end
    end
  end
end

# 注册 Tag
Liquid::Template.register_tag('last_modified', Jekyll::LastModifiedTag)
Liquid::Template.register_tag('site_last_modified', Jekyll::SiteLastModifiedTag)