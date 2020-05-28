class MultiQEMU
   attr_accessor :hostname
   attr_accessor :nr_vm
  def initialize(hostname="vm-pxe-hi1620-1p1g", nr_vm=2)
    @hostname=hostname
    @nr_vm=nr_vm
  end

  def run(i)
    loop do
      hostname = self.hostname.strip
      res=system({"hostname"=>(hostname + "-" + i.to_s)}, ENV["CCI_SRC"]+ "/providers/qemu.sh")
      if res
        next
      else
        puts "Error..."
        break
      end
    end
  end

  def start  
    puts "keep the main process started, ctrl + c quit ALL"
    self.nr_vm.times { |i|
      Thread.new{(self.run(i))}
    }
    #keep the main process started, ctrl + c quit ALL
    sleep 60*60*12
  end
end

if $PROGRAM_NAME == __FILE__ 
  t = MultiQEMU.new
  t.hostname="vm-pxe-hi1620-2p4g"
  t.nr_vm = 2
  t.start

end


