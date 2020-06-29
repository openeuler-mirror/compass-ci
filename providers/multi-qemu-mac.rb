#!/usr/bin/env ruby
# frozen_string_literal: true

# Run multiple QEMU in parallel
class MultiQEMU
  attr_accessor :hostname
  attr_accessor :nr_vm
  def initialize(hostname = 'vm-pxe-hi1620-1p1g', nr_vm = 2)
    @hostname = hostname
    @nr_vm = nr_vm
  end

  def run(seqno)
    loop do
      hostname = self.hostname.strip
      ret = system({ 'hostname' => (hostname + '-' + seqno.to_s) }, ENV['CCI_SRC'] + '/providers/qemu.sh')
      unless ret
        puts 'Error...'
        break
      end
    end
  end

  def start
    puts 'keep the main process started, ctrl + c quit ALL'
    nr_vm.times do |i|
      Thread.new { run(i) }
    end
    # keep the main process started, ctrl + c quit ALL
    sleep 60 * 60 * 12
  end
end

if $PROGRAM_NAME == __FILE__
  t = MultiQEMU.new
  t.hostname = 'vm-pxe-hi1620-2p4g'
  t.nr_vm = 2
  t.start
end
