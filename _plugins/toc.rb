module Jekyll
  # 文首内嵌 TOC:在渲染完成后扫描正文 h2-h4,自动生成可折叠目录插入文首。
  #
  # 是否启用(三态):
  #   - front matter 显式 `toc: true`  => 强制开
  #   - front matter 显式 `toc: false` => 强制关
  #   - 未指定                          => 自动判断(标题数与正文字数双达标才开)
  #
  # 设计:
  # - 复用 Kramdown(auto_ids)已为每个标题生成的 id,TOC 只是 <a href="#id"> 列表。
  # - 跳过 h1:正文 h1 已视觉降级为 h2(见 post.css),不进目录。
  # - 用 <details><nav> 语义化结构,读屏器可识别为导航,键盘可折叠展开。
  # - 宽屏默认展开、窄屏(移动端)默认折叠,由 CSS/JS 按设备控制,不在此处理。
  module TableOfContents
    # 自动判断阈值:标题数 >= MIN_HEADINGS 且正文字数 >= MIN_CHARS 才开
    MIN_HEADINGS = 4
    MIN_CHARS = 2000
    # 匹配带 id 的 h2-h4 标题,捕获:层级、id、标题文本
    HEADING = %r{<h([2-4])\b[^>]*\bid="([^"]+)"[^>]*>(.*?)</h\1>}mi
    # 标题/正文内的 HTML 标签剥掉,只留纯文本
    TAG = %r{<[^>]+>}

    # 返回 true/false:是否该为这篇文档生成 TOC
    def self.enabled?(doc, html)
      # 手动裁决优先
      return doc.data["toc"] if doc.data.key?("toc")
      # 未指定则自动判断
      auto?(html)
    end

    def self.auto?(html)
      headings = html.scan(HEADING).length
      return false if headings < MIN_HEADINGS
      text_len = html.gsub(TAG, "").gsub(/\s+/, "").length
      text_len >= MIN_CHARS
    end

    def self.build(html)
      return html unless html.is_a?(String) && html.include?("<h")

      items = []
      html.scan(HEADING) do |level, id, inner|
        text = inner.gsub(TAG, "").strip
        next if text.empty?
        items << { level: level.to_i, id: id, text: text }
      end
      return html if items.empty?

      toc = +%(<details class="post-toc" id="post-toc">\n)
      toc << %(  <summary>目录</summary>\n)
      toc << %(  <nav aria-label="文章目录">\n    <ul>\n)
      items.each do |it|
        toc << %(      <li class="toc-lv#{it[:level]}"><a href="##{it[:id]}">#{it[:text]}</a></li>\n)
      end
      toc << %(    </ul>\n  </nav>\n</details>\n)

      toc + html
    end
  end

  # 与 image_figure 同机制:单文档渲染完毕后后处理 output。
  Hooks.register :documents, :post_render do |doc|
    next unless doc.output_ext == ".html"
    doc.output = TableOfContents.build(doc.output) if TableOfContents.enabled?(doc, doc.output)
  end
end
