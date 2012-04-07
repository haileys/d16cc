module D16CC
  class NodeCompiler
    attr_reader :compiler, :ast
  
    def initialize(compiler, ast)
      @compiler, @ast = compiler, ast
      @node_stack = []
    end

    def compile
      compile_node ast
    end

    def error!(node, message)
      raise CompileError, "At #{node.pos} - #{message}"
    end
    
    def warn!(node, message)
      warn "At #{node.pos} - #{message}"
    end

  private
    def node
      @node_stack.last
    end

    def type_of(node)
      node.class.name.split("::").last
    end

    def compile_node(node)
      if respond_to? type_of(node), true
        @node_stack.push node
        send type_of(node)
        @node_stack.pop
      else
        error! node, "Node #{type_of(node)} not implemented!"
      end
    end
  
    def save_local(local, reg = "A", offset = 0)
      compiler.section << "SET #{local_ref local, offset}, #{reg}"
    end
    
    def load_local(local, reg = "A", offset = 0)
      compiler.section << "SET #{reg}, #{local_ref local, offset}"
    end
    
    def local_ref(local, offset = 0)
      "[#{-local.offset % 65536 + offset}+Z]"
    end

    def int_to_words(int, type)
      words = [int % 65536, (int / 65536) % 65536]
      if words.size > type.size
        warn! node, "Overflow in implicit constant conversion"
        word.take type.size
      else
        words + [0] * (type.size - words.size)
      end
    end
    
    # node compilers:
  
    def TranslationUnit
      node.entities.each { |child| compile_node child }
    end
  
    def FunctionDef
      if compiler.symbols[node.name]
        error! node, "Redeclaration of '#{node.name}' as different type" unless compiler.symbols[node.name] =~ node.type
      else
        compiler.symbols[node.name] = node.type
      end
      compiler.with_scope node do
        if node.type.params
          arg_offset = -2
          node.type.params.each do |param|
            type = compiler.ast_type(param.type)
            compiler.scope.set_local Scope::Local.new compiler.scope, param.name, type, arg_offset
            arg_offset -= type.size
          end
        end
        compiler.section << "SET PUSH, Z"
        compiler.section << "SET Z, SP"
        compile_node node.def
      end
    end
  
    def Block
      node.stmts.each { |stmt| compile_node stmt }
    end
  
    def Return
      return_type = compiler.ast_type(compiler.function.type.type)
      if return_type.is_a? Types::Void
        error! node, "Returning value from void function" if node.expr
      else
        error! node, "Returning no value from non-void function" unless node.expr
        compile_node node.expr
      end
      # results of expressions are always left in A, which is our return register
      compiler.section << "SET SP, Z"
      compiler.section << "SET Z, POP"
      compiler.section << "SET PC, POP"
    end
    
    def IntLiteral
      type = compiler.expression_type(node)
      error! node, "Integer literal too large. Maximum for this type is #{type.max_value}" if node.val > type.max_value
      error! node, "Integer literal too small. Minimum for this type is #{type.min_value}" if node.val < type.min_value
      compiler.section << "SET A, #{node.val % 65536}"
      compiler.section << "SET B, #{(node.val / 65536) % 65536}" if type.size == 2
    end
    
    def Negative
      if node.expr.is_a? C::IntLiteral
        type = compiler.expression_type(node.expr)
        error! node, "Integer literal too large. Maximum for this type is #{type.max_value}" if -node.expr.val > type.max_value
        error! node, "Integer literal too small. Minimum for this type is #{type.min_value}" if -node.expr.val < type.min_value
        compiler.section << "SET A, #{-node.expr.val % 65536}"
      else
        compile_node node.expr
        # compute two's complete negation:
        compiler.section << "XOR A, 0xFFFF" # binary not
        compiler.section << "ADD A, 1"
      end
    end
    
    def Call
      if node.expr.is_a? C::Variable and not compiler.scope[node.expr.name]
        unless compiler.symbols[node.expr.name]
          warn! node.expr, "implicit declaration of function '#{node.expr.name}'"
          compiler.symbols[node.expr.name] = Types::Function.new Types::Int16, *([Types::Int16] * node.args.size)
        end
      end
      # @TODO type checks on arguments
      node.args.reverse_each do |arg|
        compile_node arg
        compiler.section << "SET PUSH, A"
      end
      if node.expr.is_a? C::Variable and not compiler.scope[node.expr.name]
        compiler.section << "JSR _#{node.expr.name}"
      else
        compile_node node.expr
        compiler.section << "JSR [A]"
      end
      compiler.section << "ADD SP, #{node.args.size}"
    end
    
    def Variable
      if local = compiler.scope[node.name]
        load_local local
      else
        compiler.section << "SET A, [_#{node.name}]"
      end
    end
    
    def Add
      type1 = compiler.expression_type(node.expr1)
      type2 = compiler.expression_type(node.expr2)
      unless type1.is_a? Types::Integral and type2.is_a? Types::Integral
        error! node, "Addition can't be performed on these operand types"
      end
      if type1.size > 1 or type2.size > 1
        # 32 bit addition
        compile_node node.expr1
        compiler.section << "SET B, 0" if type1.size == 1 # zero extend
        compiler.scope.with_temp 2 do |a,b|
          save_local a, "A"
          save_local b, "B"
          compile_node node.expr2
          compiler.section << "SET B, 0" if type2.size == 1 # zero extend
          compiler.section << "ADD B, #{local_ref b}"
          compiler.section << "ADD A, #{local_ref a}"
          compiler.section << "ADD B, O"
        end
      else
        # 16 bit addition
        compile_node node.expr1
        compiler.scope.with_temp do |temp|
          save_local temp, "A"
          compile_node node.expr2
          compiler.section << "ADD A, #{local_ref temp}"
        end
      end
    end
    
    def ExpressionStatement
      if node.expr.is_a? C::Variable and node.expr.name == "__halt"
        compiler.section << "SET PC, 0xFFF0" # crash it with an illegal opcode
      else
        compile_node node.expr
      end
    end
    
    def Declaration
      type = compiler.ast_type node.type
      declarators = node.declarators.map { |d| d.is_a?(Array) ? d.first : d }
      if compiler.scope
        declarators.each do |declarator|
          local = compiler.scope.declare declarator.name, type
          if declarator.init
            if init = ConstantFolder.fold(self, declarator.init)
              int_to_words(init, type).each_with_index do |word, offset|
                compiler.section << "SET #{local_ref local, offset}, #{word}"
              end
            else
              #
            end
          end
        end
      else
        declarators.each do |declarator|
          error! "Redeclaration of global '#{declarator.name}'" if compiler.symbols[declarator.name]
          compiler.symbols["_#{declarator.name}"] = type
          declarator.init ||= C::IntLiteral.new(0)
          if type.is_a? Types::Integral
            if init = ConstantFolder.fold(self, declarator.init)
              int_to_words(init, type).each_with_index do |word, offset|
                # encoding the offset into the label is a hack to compensate for this shoddy assembler
                compiler.sections["_#{declarator.name}"] << ":_#{declarator.name}___word_#{offset} DW #{word}"
              end
            else
              error! node, "Cannot initialize global with non-constant expression"
            end
          else
            error! node, "initializion of non-integral types not supported yet (#{declarator.init.class})"
          end
        end
      end
    end
    
    def Assign
      rval_type = compiler.expression_type node.rval
      compile_node node.rval
      case node.lval
      when C::Variable
        if local = compiler.scope[node.lval.name]
          if local.type.is_a? Types::Integral and rval_type.is_a? Types::Integral
            if local.type.size < rval_type.size
              warn! node, "Value truncated in assignment"
              save_local local, "A"
            elsif local.type.size == rval_type.size
              save_local local, "A"
              save_local local, "B", 1 if local.type.size == 2
            else
              # zero extend, TODO sign extend instead
              save_local local, "A"
              compiler.section << "SET #{local_ref local, 1}, 0"
            end
          else
            error! node, "Type mismatch in assignment"
          end
        elsif global = compiler.symbols["_#{node.lval.name}"]
          error! node, "Invalid lval in assignment" if global.is_a? Types::Function
          if global.is_a? Types::Integral and rval_type.is_a? Types::Integral
            if global.size < rval_type.size
              warn! node, "Value truncated in assignment"
              compiler.section << "SET [_#{node.lval.name}], A"
            elsif global.size == rval_type.size  
              compiler.section << "SET [_#{node.lval.name}], A"
              compiler.section << "SET [_#{node.lval.name}___word_1], B" if global.size == 2
            else
              # zero extend, TODO sign extend instead
              compiler.section << "SET [_#{node.lval.name}], A"
              compiler.section << "SET [_#{node.lval.name}___word_1], 0"
            end
          else
            error! node, "Type mismatch in assignment"
          end
        else
          require "pry"
          pry binding
          error! node, "Wtf"
        end
      else
        raise "unimplemented lval type #{node.lval.class}"
      end
    end
  end
end