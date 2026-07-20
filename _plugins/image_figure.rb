module Jekyll
  # 把「只含单个 <img> 的段落」包装为 <figure><img><figcaption></figure>。
  #
  # 演变：
  # 1) 最初是高优先级的 Markdown Converter，在 Kramdown 解析前就把图片语法
  #    换成原始 <figure> 块。但 Kramdown 的 HTML 块解析器只认「行首 + 后接空行」
  #    的原始标签，当 <figure> 落在正文末尾或与相邻段落合并时不再被识别，
  #    浏览器自动补全后多出一个孤立的 </figure>。
  # 2) 改成 Generator 在 generate 里改 doc.output —— 但 Jekyll 3.9 中 generate
  #    运行时页面 output 尚未渲染（懒计算），改动不生效，figure 全部消失。
  #
  # 现方案：用 Hook 在每个文档/页面「渲染完成后」后处理其 HTML。此时结构已定，
  # 生成的 <figure> 永远完整、正确嵌套，从根上消除多余 </figure>，且与
  # 渲染顺序、incremental 无关。
  module ImageFigure
    # 匹配只包含单个 <img> 的段落
    IMG_PARA = %r{<p>\s*(<img\b[^>]*>)\s*</p>}i

    def self.wrap(html)
      return html unless html.is_a?(String) && html.include?("<img")

      html.gsub(IMG_PARA) do
        img_tag = Regexp.last_match(1)
        alt_text = extract_alt(img_tag)

        figure = +"<figure>\n  #{img_tag}\n"
        figure << "  <figcaption>#{alt_text}</figcaption>\n" unless alt_text.empty?
        figure << "</figure>"
        figure
      end
    end

    # 取出 alt 属性（支持单双引号），未设置或为空时返回空串
    def self.extract_alt(img_tag)
      if img_tag =~ /\balt\s*=\s*"([^"]*)"/i || img_tag =~ /\balt\s*=\s*'([^']*)'/i
        Regexp.last_match(1).to_s.strip
      else
        ""
      end
    end
  end

  # :post_render 在单个文档渲染完毕、写入 output 之后触发
  Hooks.register :documents, :post_render do |doc|
    doc.output = ImageFigure.wrap(doc.output)
  end

  Hooks.register :pages, :post_render do |page|
    page.output = ImageFigure.wrap(page.output)
  end
end
