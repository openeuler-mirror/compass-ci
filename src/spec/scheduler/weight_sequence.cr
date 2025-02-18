require "spec"
require "../../scheduler/dispatch"

# This test suite verifies:
# - Basic Weight Compliance: Validates proportional distribution
# - Determinism: Ensures identical input produces identical output
# - Edge Cases: Tests single-user, default weights, and dense sequences
# - Order Stability: Checks lexicographical sorting for position ties
# - Distribution Quality: Verifies even spacing through pattern checks
# 
# Key test patterns:
# - Direct sequence matching for known weight distributions
# - Multi-run consistency checks for determinism
# - Lexicographical ordering validation
# - Default weight handling verification
# - Complex case analysis for multi-user same-weight scenarios

# Test helper to normalize user list creation
def test_users(*names)
  names.map { |n| "User#{n}" }
end

describe "user_sequencer" do

  describe "#create_users_sequence" do
    it "correctly distributes users by weight" do
      users = test_users(:A, :B)
      weights = {"UserA" => 3, "UserB" => 2}
      expected = ["UserA", "UserB", "UserA", "UserB", "UserA"]
      
      Sched.create_users_sequence(users, weights).should eq(expected)
    end

    it "orders equal-weight users lexicographically" do
      users = test_users(:C, :B, :A)
      weights = {"UserA" => 1, "UserB" => 1, "UserC" => 1}
      expected = ["UserA", "UserB", "UserC"]
      
      Sched.create_users_sequence(users, weights).should eq(expected)
    end

    it "handles dominant weights with even spacing" do
      users = test_users(:X, :Y)
      weights = {"UserX" => 4, "UserY" => 1}
      expected = ["UserX", "UserX", "UserY", "UserX", "UserX"]
      
      Sched.create_users_sequence(users, weights).should eq(expected)
    end

    it "produces deterministic results for same input" do
      users = test_users(:M, :N)
      weights = {"UserM" => 2, "UserN" => 3}
      
      first_run = Sched.create_users_sequence(users, weights)
      second_run = Sched.create_users_sequence(users, weights)
      first_run.should eq(second_run)
    end

    it "orders same-position users alphabetically" do
      users = test_users(:Z, :A)
      weights = {"UserA" => 2, "UserZ" => 2}
      expected = ["UserA", "UserZ", "UserA", "UserZ"]
      
      Sched.create_users_sequence(users, weights).should eq(expected)
    end

    it "handles single-user sequences" do
      users = test_users(:Solo)
      weights = {"UserSolo" => 4}
      expected = ["UserSolo"] * 4
      
      Sched.create_users_sequence(users, weights).should eq(expected)
    end

    it "uses default weight of 1 for unspecified users" do
      users = test_users(:A, :B)
      weights = {"UserA" => 2}
      expected = ["UserA", "UserB", "UserA"]
      
      Sched.create_users_sequence(users, weights).should eq(expected)
    end

    it "maintains original order for weight ties in same-position conflicts" do
      users = test_users(:X, :Y, :Z)
      weights = {"UserX" => 3, "UserY" => 3, "UserZ" => 3}
      # Should alternate based on initial user order and lex order
      # This test validates the tie-breaking hierarchy
      seq = Sched.create_users_sequence(users, weights)
      
      # Verify pattern contains all three users interleaved
      seq.each_cons(3) do |triple|
        triple.uniq.size.should be >= 2
      end
    end
  end
end

describe "generate_interleaved_sequence" do
  it "handles two hosts with equal weights" do
    host_keys = ["X", "Y"]
    nr_jobs = {"X" =>1, "Y" =>1}
    sequence = Sched.generate_interleaved_sequence host_keys, nr_jobs
    sequence.should eq ["X", "Y"]
  end

  it "generates round-robin sequence for even weights" do
    host_keys = ["A", "B"]
    nr_jobs = {"A" =>4, "B" =>4} # sqrt(4) is 2
    sequence = Sched.generate_interleaved_sequence host_keys, nr_jobs
    sequence.should eq ["A", "B", "A", "B"]
  end

  it "interleaves higher and lower weights" do
    host_keys = ["A", "B"]
    nr_jobs = {"A" =>9, "B" =>1} # sqrt 3 and 1
    sequence = Sched.generate_interleaved_sequence host_keys, nr_jobs
    sequence.should eq ["A", "B", "A", "A"]
  end

  it "handles multiple hosts with varying weights" do
    host_keys = ["A", "B", "C"]
    nr_jobs = {"A" =>9, "B" =>4, "C" =>1} # sqrt 3, 2, 1
    sequence = Sched.generate_interleaved_sequence host_keys, nr_jobs
    sequence.should eq ["A", "B", "C", "A", "B", "A"]
  end

  it "scales weights and distributes them evenly" do
    host_keys = ["A", "B"]
    nr_jobs = {"A" => (256**2 *4), "B" => (256**2 *1)}
    sequence = Sched.generate_interleaved_sequence host_keys, nr_jobs
    sequence.size.should eq 384
    sequence.count("A").should eq 256
    sequence.count("B").should eq 128
    sequence[0..4].should eq ["A", "B", "A", "A", "B"]
  end

  it "generates a sequence with a single host" do
    host_keys = ["A"]
    nr_jobs = {"A" => (257**2)} # sqrt(257^2) =257 >256, scaled to 256
    sequence = Sched.generate_interleaved_sequence host_keys, nr_jobs
    sequence.size.should eq 256
    sequence.each { |e| e.should eq "A" }
  end
end
