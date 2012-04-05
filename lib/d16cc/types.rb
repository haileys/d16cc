module D16CC::Types
  class Void
    def self.new
      @@void ||= allocate
    end
  end
  
  class Integral
    def initialize(opts = {})
      opts.each { |k,v| instance_variable_set "@#{k}", v }
    end
    
    def size
      @size
    end
    
    def min_value
      if signed?
        -((2**(16*size))/2)
      else
        0
      end
    end
    
    def max_value
      if signed?
        (2**(16*size))/2 - 1
      else
        (2**(16*size)) - 1
      end
    end
    
    def scalar?
      true
    end
    
    def integral?
      true
    end
    
    def signed?
      @signed
    end
    
    def unsigned?
      not signed?
    end
    
    def as_signed
      if signed?
        self
      else
        Integral.new size: size, signed: true
      end
    end
    
    def as_unsigned
      if unsigned?
        self
      else
        Integral.new size: size, signed: false
      end
    end
  end
  
  class Struct
    class Member
      attr_reader :struct, :name, :type, :offset
      
      def initialize(struct, name, type, offset)
        @struct, @name, @type, @offset = struct, name, type, offset
      end
    end
    
    def initialize(members)
      @members = members
    end
    
    def scalar?
      false
    end
    
    def members
      @members.keys
    end
    
    def size
      @size ||= @members.map { |name,type| type.size }.reduce(:+)
    end
    
    def [](member)
      if @members[member]
        Member.new self, name, @members[member], offset_of(member)
      end
    end
    
    def offset_of(member)
      @members.take_while { |name,type| name != member }.map { |name,type| type.size }.reduce(:+)
    end
    
    def type_of(member)
      @members[member]
    end
  end
  
  class Union < Struct
    def size
      @size ||= @members.map { |name,type| type.size }.max
    end
    
    def offset_of(member)
      0
    end
  end
  
  class Function
    attr_reader :ret, :args
    
    def initialize(ret, args)
      @ret, @args = ret, args
    end
    
    def scalar?
      true
    end
    
    def size
      1
    end
  end
  
  Int16 = Integral.new size: 1, signed: true
  Int32 = Integral.new size: 2, signed: true
  UInt16 = Int16.as_unsigned
  UInt32 = Int32.as_unsigned
end