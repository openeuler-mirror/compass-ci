require "spec"
require "../../lib/host.cr"
require "../../lib/manticore.cr"

def flatten_hash(hash : Hash)
  Manticore::FullTextWords.flatten_hash(JSON.parse(hash.to_json).as_h)
end

def break_full_text_words(line : String)
  Manticore::FullTextWords.break_full_text_words(line)
end

def create_full_text_kv(hash : Hash)
  Manticore::FullTextWords.create_full_text_kv(JSON.parse(hash.to_json).as_h, HostInfo::FULL_TEXT_KEYS)
end

describe "flatten_hash" do
  it "flattens a simple hash" do
    input = {"a" => 1, "b" => 2}
    expected = {"a" => 1, "b" => 2}
    flatten_hash(input).should eq(JSON.parse(expected.to_json))
  end

  it "flattens a nested hash" do
    input = {"a" => {"b" => 1, "c" => 2}}
    expected = {"a.b" => 1, "a.c" => 2}
    flatten_hash(input).should eq(JSON.parse(expected.to_json))
  end

  it "flattens a hash with arrays" do
    input = {"a" => [1, 2, 3]}
    expected = {"a" => [1, 2, 3]}
    flatten_hash(input).should eq(JSON.parse(expected.to_json))
  end

  it "flattens a hash with nested arrays and hashes" do
    input = {"a" => {"b" => [1, 2], "c" => {"d" => 3}}}
    expected = {"a.b" => [1, 2], "a.c.d" => 3}
    flatten_hash(input).should eq(JSON.parse(expected.to_json))
  end

  it "flattens a hash with arrays of hashes" do
    input = {"a" => [{"b" => 1}, {"c" => 2}]}
    expected = {"a.b" => 1, "a.c" => 2}
    flatten_hash(input).should eq(JSON.parse(expected.to_json))
  end

  it "flattens a deeply nested hash" do
    input = {"a" => {"b" => {"c" => {"d" => 1}}}}
    expected = {"a.b.c.d" => 1}
    flatten_hash(input).should eq(JSON.parse(expected.to_json))
  end

  it "handles empty hash" do
    input = {} of String => String
    expected = {} of String => String
    flatten_hash(input).should eq(JSON.parse(expected.to_json))
  end

#  it "handles empty arrays" do
#    input = {"a" => [] of String}
#    expected = {"a" => [] of String}
#    flatten_hash(input).should eq(JSON.parse(expected.to_json))
#  end

#  it "handles nested arrays of hashes with different keys" do
#    input = {"a" => [{"b" => 1}, {"c" => 2}, {"d" => {"e" => 3}}]}
#    expected = {"a.b" => [1], "a.c" => [2], "a.d.e" => [3]}
#    flatten_hash(input).should eq(JSON.parse(expected.to_json))
#  end

  it "handles nested arrays of hashes with same keys" do
    input = {"a" => [{"b" => 1}, {"b" => 2}]}
    expected = {"a.b" => [1, 2]}
    flatten_hash(input).should eq(JSON.parse(expected.to_json))
  end

#  it "handles nested arrays of hashes with mixed keys" do
#    input = {"a" => [{"b" => 1}, {"c" => 2}, {"b" => 3}]}
#    expected = {"a.b" => [1, 3], "a.c" => [2]}
#    flatten_hash(input).should eq(JSON.parse(expected.to_json))
#  end

end

describe "FullText Processor" do
  it "processes Intel CPU string correctly" do
    input = "Intel(R) Xeon(R) CPU E5-2680 v3 @ 2.50GHz"
    expected = ["Intel", "Xeon", "CPU", "E5-2680", "v3", "2.50GHz"]
    break_full_text_words(input).should eq expected
  end

  it "processes DIMM DRAM string correctly" do
    input = "DIMM DRAM Synchronous Registered (Buffered) 2133 MHz (0.5 ns)"
    expected = ["DIMM", "DRAM", "Synchronous", "Registered", "Buffered", "2133MHz", "0.5ns"]
    break_full_text_words(input).should eq expected
  end

  it "processes 768 KiB correctly" do
    input = "768 KiB"
    expected = ["768KiB"]
    break_full_text_words(input).should eq expected
  end

  it "processes Huawei string correctly" do
    input = "Huawei Technologies Co., Ltd."
    expected = ["Huawei", "Technologies", "Co", "Ltd"]
    break_full_text_words(input).should eq expected
  end

  it "processes Hi1710 string correctly" do
    input = "Hi1710 [iBMC Intelligent Management system chip w/VGA support]"
    expected = ["Hi1710", "iBMC", "Intelligent", "Management", "system", "chip", "w/VGA", "support"]
    break_full_text_words(input).should eq expected
  end

  it "handles numbers with units correctly" do
    break_full_text_words("5 GHz").should eq ["5GHz"]
    break_full_text_words("100 MB").should eq ["100MB"]
    break_full_text_words("3.5 in").should eq ["3.5in"]
  end

  it "removes pure symbol words" do
    break_full_text_words("Hello!!! ~~World~~").should eq ["Hello", "World"]
    break_full_text_words("Test @ # $ %").should eq ["Test"]
  end

  it "handles complex mixed words" do
    break_full_text_words("ABC-123 (X) 4.5-6.7GHz").should eq ["ABC-123", "X", "4.5-6.7GHz"]
  end

end

describe "create_full_text_kv" do
  it "handles simple nested structures" do
    host_info = {
      "bios" => {
        "vendor" => "Insyde Corp.",
        "version" => "5.13"
      }
    }

    expected_output = [
      "bios.vendor=Insyde",
      "bios.vendor=Corp",
      "bios.version=5.13"
    ]

    create_full_text_kv(host_info).should eq(expected_output)
  end

  it "handles nested structures with arrays" do
    host_info = {
      "bios" => {
        "vendor" => ["Insyde Corp.", "Phoenix Technologies Ltd."],
        "version" => "5.13"
      }
    }

    expected_output = [
      "bios.vendor=Insyde",
      "bios.vendor=Corp",
      "bios.vendor=Phoenix",
      "bios.vendor=Technologies",
      "bios.vendor=Ltd",
      "bios.version=5.13"
    ]

    create_full_text_kv(host_info).should eq(expected_output)
  end

  it "handles nested structures with multiple levels" do
    host_info = {
      "system" => {
        "manufacturer" => "Huawei",
        "version" => "V100R003",
        "product_name" => "RH2288H V3"
      }
    }

    expected_output = [
      "system.manufacturer=Huawei",
      "system.version=V100R003",
      "system.product_name=RH2288H",
      "system.product_name=V3"
    ]

    create_full_text_kv(host_info).should eq(expected_output)
  end

  it "handles nested structures with arrays of hashes" do
    host_info = {
      "cpu" => {
        "family" => ["Xeon", "Xeon"],
        "manufacturer" => ["Intel(R) Corporation", "Intel(R) Corporation"],
        "version" => ["Intel(R) Xeon(R) CPU E5-2680 v3 @ 2.50GHz", "Intel(R) Xeon(R) CPU E5-2680 v3 @ 2.50GHz"]
      }
    }

    expected_output = [
      "cpu.family=Xeon",
      "cpu.manufacturer=Intel",
      "cpu.manufacturer=Corporation",
      "cpu.version=Intel",
      "cpu.version=Xeon",
      "cpu.version=CPU",
      "cpu.version=E5-2680",
      "cpu.version=v3",
      "cpu.version=2.50GHz"
    ]

    create_full_text_kv(host_info).should eq(expected_output)
  end

  it "handles nested structures with mixed types" do
    host_info = {
      "memory_info" => {
        "total_size" => "320g",
        "bank" => [
          {
            "description" => "DIMM DRAM Synchronous Registered (Buffered) 2133 MHz (0.5 ns)",
            "product" => "36ASF2G72PZ-2G1A2",
            "vendor" => "Micron",
            "size" => "17179869184 bytes"
          }
        ]
      }
    }

    expected_output = [
      "memory_info.total_size=320g",
      "memory_info.bank.description=DIMM",
      "memory_info.bank.description=DRAM",
      "memory_info.bank.description=Synchronous",
      "memory_info.bank.description=Registered",
      "memory_info.bank.description=Buffered",
      "memory_info.bank.description=2133MHz",
      "memory_info.bank.description=0.5ns",
      "memory_info.bank.product=36ASF2G72PZ-2G1A2",
      "memory_info.bank.vendor=Micron",
      "memory_info.bank.size=17179869184bytes",
    ]

    create_full_text_kv(host_info).should eq(expected_output)
  end

  it "handles empty values" do
    host_info = {
      "bios" => {
        "vendor" => "Insyde Corp.",
        "version" => ""
      }
    }

    expected_output = [
      "bios.vendor=Insyde",
      "bios.vendor=Corp"
    ]

    create_full_text_kv(host_info).should eq(expected_output)
  end

  it "handles non-selected top-level keys" do
    host_info = {
      "bios" => {
        "vendor" => "Insyde Corp."
      },
      "network" => {
        "interface" => "eth0"
      },
      "unknown" => {
        "value" => "test"
      }
    }

    expected_output = [
      "bios.vendor=Insyde",
      "bios.vendor=Corp",
      "network.interface=eth0"
    ]

    create_full_text_kv(host_info).should eq(expected_output)
  end

  it "handles duplicate values" do
    host_info = {
      "system" => {
        "manufacturer" => "Huawei",
        "version" => "V100R003",
        "product_name" => "RH2288H V3"
      },
      "baseboard" => {
        "manufacturer" => "Huawei"
      }
    }

    expected_output = [
      "system.manufacturer=Huawei",
      "system.version=V100R003",
      "system.product_name=RH2288H",
      "system.product_name=V3",
      "baseboard.manufacturer=Huawei"
    ]

    create_full_text_kv(host_info).should eq(expected_output)
  end
end
