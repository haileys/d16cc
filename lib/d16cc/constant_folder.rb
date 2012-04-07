module D16CC
  class ConstantFolder
    attr_reader :compiler
    
    def self.fold(compiler, node)
      new(compiler).fold node
    rescue CompileError => e
      puts e
      false
    end
    
    def initialize(compiler)
      @compiler, @node_stack = compiler, []
    end
    
    def fold(node)
      fold_node node
    end
    
  private
    def node
      @node_stack.last
    end
  
    def type_of(node)
      node.class.name.split("::").last
    end
    
    def fold_node(node)
      if respond_to? type_of(node), true
        begin
          @node_stack.push node
          send type_of(node)
        ensure
          @node_stack.pop
        end
      else
        compiler.error! node, "Can't fold constant #{type_of node}"
      end
    end
    
    #
    
    def IntLiteral
      node.val
    end
    
    def Negative
      -fold_node(node.expr)
    end
  end
end