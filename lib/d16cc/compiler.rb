module D16CC
  class Compiler
    class Section
      attr_reader :name, :lines
    
      def initialize(name)
        @name, @lines = name, []
      end
    
      def <<(line)
        lines << line.to_s
      end
    
      def to_s
        [":#{name}", *lines.map { |l| "    #{l}" }].join "\n"
      end
    end
  
    attr_reader :types, :source, :sections, :symbols
  
    def initialize(source)
      @source = source
      @sections = Hash.new { |h,k| h[k] = Section.new(k) }
      @symbols = {}
      @types = {
        "char"  => Types::Int16,
        "short" => Types::Int16,
        "int"   => Types::Int16,
        "long"  => Types::Int32,
      }
      @types.keys.each do |name|
        @types["unsigned #{name}"] = @types[name].as_unsigned
      end
    end
  
    def compile
      @ast = C.parse source
      @node_compiler = NodeCompiler.new self, @ast
      @node_compiler.compile
    end
  
    def asm
      [sections["_main"], *sections.reject { |k,v| k == "_main" }.values].map(&:to_s).join("\n\n")
    end

    def section
      scope.section
    end

    def scope
      @current_scope
    end
  
    def function
      scope.function
    end
  
    def with_scope(fn)
      @current_scope = Scope.new sections["_#{fn.name}"], fn
      yield
      @current_scope = nil
    end
  
    def ast_type(node)
      case node
      when C::Int
        case node.longness
        when 1  then Types::Int32
        when 0  then Types::Int16
        when -1 then Types::Int16
        else raise "wtf"
        end
      else
        raise "can't find own type for #{node.class}!"
        require "pry"
        pry binding
      end
    end
  
    def expression_type(node)
      case node
      when C::IntLiteral
        type = (node.suffix && node.suffix.downcase.include?("l")) ? Types::Int32 : Types::Int16
        type = type.as_unsigned if node.suffix and node.suffix.downcase.include? "u"
        type
      when C::Variable
        if scope[node.name]
          scope[node.name].type
        elsif symbols["_#{node.name}"]
          symbols["_#{node.name}"]
        else
          @node_compiler.error! node, "Undefined identifier #{node.name}"
        end
      when C::Negative
        expression_type node.expr
      else
        raise "can't find expression type in #{node.class}!"
        require "pry"
        pry binding
      end
    end
  end
end