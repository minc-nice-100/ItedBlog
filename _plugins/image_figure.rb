module Jekyll
  # 将 <p><img ...></p> 包装为 <figure><img><figcaption></figure>
  #
  # 旧实现是一个高优先级的 Markdown Converter，直接把图片语法替换成
  # 原始 <figure> HTML 块。但 Kramdown 的 HTML 块解析器只认“行首 + 后接空行”
  # 的原始标签；当 <figure> 落在正文末尾或与相邻段落合并时，标签就不再被
  # 正常识别，浏览器自动补全标签后便会多出一个孤立的 </figure>。
  #
  # 现在改为在 Kramdown 渲染完成后的 HTML 上做后处理：此时文档结构已经
  # 定型，生成的 <figure> 永远是完整、正确嵌套的，从根本上消除多余的 </figure>。
  class ImageFigureConverter < Generator
    safe true
    priority :low

    def generate(site)
      (site.posts.docs + site.pages).each do |doc|
        next unless doc.output.is_a?(String)
        doc.output = wrap_images(doc.output)
      end
    end

    private

    # 匹配只包含单个 <img> 的段落，将其提升为 <figure>
    def wrap_images(html)
      html.gsub(%r{<p>\s*(<img\b[^>]*>)\s*</p>}i) do
        img_tag = Regexp.last_match(1)
        alt_text = extract_alt(img_tag)

        figure = +"<figure>\n  #{img_tag}\n"
        figure << "  <figcaption>#{alt_text}</figcaption>\n" unless alt_text.empty?
        figure << "</figure>"
        figure
      end
    end

    # 从 img 标签中取出 alt 属性（支持单双引号），未设置时返回空串
    def extract_alt(img_tag)
      if img_tag =~ /\balt\s*=\s*"([^"]*)"/i || img_tag =~ /\balt\s*=\s*'([^']*)'/i
        Regexp.last_match(1).to_s.strip
      else
        ""
      end
    end
  end
end
