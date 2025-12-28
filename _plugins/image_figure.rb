module Jekyll
  class ImageFigureConverter < Converter
    priority :high
    
    def matches(ext)
      ext =~ /^\.(md|markdown)$/i
    end

    def output_ext(ext)
      ".html"
    end

    def convert(content)
      # 匹配Markdown图片语法：![alt text](image.jpg "title")
      content.gsub(/!\[(.*?)\]\((.*?)(?:\s+"(.*?)")?\)/) do |match|
        alt_text = $1
        image_url = $2
        title_text = $3
        
        # 构建figure标签，保留懒加载属性
        figure_html = <<~HTML
        <figure>
          <img src="#{image_url}" alt="#{alt_text}" loading="lazy"#{title_text ? " title=\"#{title_text}\"" : ""}>
          <figcaption>#{alt_text}</figcaption>
        </figure>
        HTML
        
        figure_html.strip
      end
    end
  end
end