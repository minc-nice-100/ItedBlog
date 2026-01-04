# frozen_string_literal: true

module Kramdown
  module Parser
    class KramdownFigure < Kramdown::Parser::Kramdown
      # 块级图片的正则（kramdown 原有定义）
      IMAGE_START = /^!\[([^\]]*)\]\((#{URL_REGEX_CHARS}+)(?: +["(](.+?)[")])?\)/

      def initialize(source, options)
        super
        # 覆盖原有的图片解析定义
        @block_parsers = @block_parsers.dup
        @block_parsers.unshift(:figure_image)  # 优先使用我们自定义的
      end

      # 自定义块级图片解析
      define_parser(:figure_image, /^!\[/, nil)

      def parse_figure_image
        @src.pos += @src.matched_size

        alt   = @src[1] || ''
        url   = @src[2]
        title = @src[3]

        # 构建 figure 元素树
        figure_el = Element.new(:figure)

        img_el = Element.new(:img, nil, nil, {
          'src'     => url,
          'alt'     => alt,
          'loading' => 'lazy'
        })
        img_el.attr['title'] = title if title && !title.empty?

        figcaption_el = Element.new(:figcaption)
        figcaption_el.children = @tree.children.dup  # 复制当前文本节点作为 caption
        figcaption_el.children << Element.new(:text, alt)

        figure_el.children << img_el
        figure_el.children << figcaption_el

        @tree.children << figure_el

        true
      end
    end
  end

  module Converter
    class Html
      # 确保 figure 直接输出为 <figure> 而不是被包装成 <p>
      alias_method :orig_convert_figure, :convert_figure unless method_defined?(:orig_convert_figure)

      def convert_figure(el, indent)
        "<figure#{html_attributes(el.attr)}>\n" +
          inner(el, indent + 2) +
          "\n</figure>"
      end

      # 可选：让 figcaption 内容被正确处理（支持内联 markdown）
      def convert_figcaption(el, indent)
        "<figcaption>#{inner(el, indent)}</figcaption>"
      end
    end
  end
end

# 注册自定义解析器（优先使用）
Kramdown::Parser.add_parser(:kramdown_figure, Kramdown::Parser::KramdownFigure)