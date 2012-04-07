module D16CC
  class Scope
    class Local
      attr_reader :scope, :name, :type, :offset
      
      def initialize(scope, name, type, offset)
        @scope, @name, @type, @offset = scope, name, type, offset
      end
    end
    
    attr_reader :section, :function, :size
    
    def initialize(section, function)
      @section = section
      @function = function
      @variables = {}
      @temp = []
      @size = 1
    end
    
    def acquire_temp
      if @temp.any?
        @temp.pop
      else
        local = Local.new self, "___temp_#{@size}", Types::Int32, @size
        @size += 1
        local
      end
    end
    
    def release_temp(temp)
      @temp << temp
    end
    
    def with_temp(count = 1)
      temps = count.times.map { acquire_temp }
      yield(*temps)
    ensure
      temps.each { |temp| release_temp temp }
    end
    
    def set_local(local)
      if @variables[local.name]
        raise "Can't redeclare #{local.name}"
      end
      @variables[local.name] = local
    end
    
    def declare(name, type)
      set_local(Local.new(self, name, type, @size)).tap do
        @size += type.size
      end
    end
    
    def [](name)
      @variables[name]
    end
  end
end