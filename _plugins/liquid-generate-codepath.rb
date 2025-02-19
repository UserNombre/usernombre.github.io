module Jekyll
  module CodepathFilter
    attr_accessor :repositories
    attr_accessor :definitions
    attr_accessor :tab_width
    attr_accessor :last_repository

    def generate_codepath(yaml, name, width)
      self.repositories = yaml["repositories"]
      self.definitions = yaml["definitions"]
      self.tab_width = width
      self.last_repository = nil
      inner = generate_lines(nil, yaml["codepaths"][name], 0)
      html = "<div class='highlighter-rouge unselectable'><pre><code>#{inner}</code></pre></div>"
      return html
    end

    def generate_lines(parent, nodes, depth)
      html = ""
      nodes.each do |node|
        line = generate_line(parent, node, depth)
        html += "#{line}\n"
        if node.key?("children")
          html += generate_lines(node, node["children"], depth + 1)
        end
      end
      return html
    end

    def generate_line(parent, node, depth)
      html = ""
      html += generate_indentation(parent, node, depth)
      html += generate_code(parent, node)
      html += generate_definition(parent, node)
      return html
    end

    def generate_indentation(parent, node, depth)
      html = ""
      if parent == nil or not node.key?("line")
        html = " " * self.tab_width * depth
      else
        html = " " * self.tab_width * (depth - 1)
        definition = self.definitions[parent["call"]]
        repository = self.repositories[definition["repository"]]
        url = repository["format"]
          .gsub("${file}", definition["file"])
          .gsub("${line}", node["line"].to_s)
        html += "<a href='#{url}'>>#{" " * (self.tab_width - 1)}</a>"
      end
      return html
    end

    def generate_code(parent, node)
      html = ""
      if node.key?("call")
        definition = self.definitions[node["call"]]
        html = definition.key?("symbol") ? definition["symbol"] : node["call"]
      elsif node.key?("code")
        html = node["code"]
      end
      html = "<span class='selectable'>#{html}</span>"
      # FIXME: comment/footnotes style
      # https://developer.mozilla.org/en-US/docs/Web/Accessibility/ARIA/Roles/tooltip_role#escape
      if node.key?("comment")
        html = "<span title='#{node["comment"]}'>#{html}</span>"
      end
      if node.key?("footnote")
        html += "<span markdown='1'>[^#{node["footnote"]}]</span>"
      end
      return html
    end

    def generate_definition(parent, node)
      html = ""
      if node.key?("call")
        definition = self.definitions[node["call"]]
        repository = self.repositories[definition["repository"]]
        url = repository["format"]
          .gsub("${file}", definition["file"])
          .gsub("${line}", definition["line"].to_s)
        path = definition["file"]
        if self.last_repository != definition["repository"]
          path += "@#{definition["repository"]}"
        end
        html = " <<a href='#{url}'>#{path}</a>>"
        self.last_repository = definition["repository"]
      end
      return html
    end
  end
end

Liquid::Template.register_filter(Jekyll::CodepathFilter)
