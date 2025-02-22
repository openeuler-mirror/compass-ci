require "spec"
require "yaml"
require "../job.cr"
require "../plugins/cluster.cr"

# mock class
class MockJob < JobHash
  def initialize
    super
    @hash_hhh["daemon"] = HashHH.new
    @hash_hhh["program"] = HashHH.new
  end
end

describe "ClusterJobSystem" do

  describe "full integration" do
    it "processes server-client cluster" do
      jobs = [
        MockJob.new.tap do |j|
          j.id = "server1"
          j.hash_hhh["daemon"]["web"] = {"if-role" => "server"}
        end,
        MockJob.new.tap do |j|
          j.id = "client1"
          j.hash_hhh["program"]["app"] = {
            "if-role" => "client",
            "depends-on" => "web"
          }
        end
      ]
      jobid2roles = {"server1" => "server", "client1" => "client"}

      Cluster.cluster_depends2scripts(jobs, jobid2roles)

      # Verify server post-script
      server_daemon = jobs[0].hash_hhh["daemon"]["web"]
      server_daemon["post-script"].should contain("wait-jobs.sh client1.milestones=app-done") if server_daemon

      # Verify client pre-script
      client_program = jobs[1].hash_hhh["program"]["app"]
      client_program["pre-script"].should contain("wait-jobs.sh server1.milestones=web-ready") if client_program
    end
  end
end

describe "cluster_depends2scripts complex scenarios" do
  it "handles jobs with multiple roles" do
    jobs = [
      MockJob.new.tap do |j|
        j.id = "multi1"
        j.hash_hhh["daemon"]["db"] = {"if-role" => "database,backup"}
      end
    ]
    jobid2roles = {"multi1" => "database,backup"}

    Cluster.cluster_depends2scripts(jobs, jobid2roles)

    roles = Cluster.get_roles(jobs.first)
    roles.should contain("database")
    roles.should contain("backup")
  end

  it "processes multi-tier dependencies" do
    jobs = [
      MockJob.new.tap do |j|
        j.id = "web"
        j.hash_hhh["program"]["app"] = {
          "depends-on" => "redis",
          "if-role" => "frontend"
        }
      end,
      MockJob.new.tap do |j|
        j.id = "cache"
        j.hash_hhh["daemon"]["redis"] = {
          "depends-on" => "postgres",
          "if-role" => "middleware"
        }
      end,
      MockJob.new.tap do |j|
        j.id = "db"
        j.hash_hhh["daemon"]["postgres"] = {"if-role" => "database"}
      end
    ]
    jobid2roles = {"web" => "frontend", "cache" => "middleware", "db" => "database"}

    Cluster.cluster_depends2scripts(jobs, jobid2roles)

    web_pre = jobs[0].hash_hhh["program"]["app"].not_nil!.["pre-script"]
    web_pre.should contain("wait-jobs.sh cache.milestones=redis-ready")

    cache_pre = jobs[1].hash_hhh["daemon"]["redis"].not_nil!.["pre-script"]
    cache_pre.should contain("wait-jobs.sh db.milestones=postgres-ready")
  end

  it "ignores self-dependencies" do
    job = MockJob.new.tap do |j|
      j.id = "self"
      j.hash_hhh["daemon"]["loop"] = {
        "depends-on" => "loop",
        "if-role" => "test"
      }
    end
    jobid2roles = {"self" => "test"}

    Cluster.cluster_depends2scripts([job], jobid2roles)

    job.hash_hhh["daemon"]["loop"].not_nil!.["pre-script"]?.should be_nil
  end

  it "handles circular dependencies gracefully" do
    jobs = [
      MockJob.new.tap do |j|
        j.id = "a"
        j.hash_hhh["program"]["x"] = {
          "depends-on" => "y",
          "if-role" => "circle"
        }
      end,
      MockJob.new.tap do |j|
        j.id = "b"
        j.hash_hhh["program"]["y"] = {
          "depends-on" => "x",
          "if-role" => "circle"
        }
      end
    ]
    jobid2roles = {"a" => "circle", "b" => "circle"}

    Cluster.cluster_depends2scripts(jobs, jobid2roles)

    # Shouldn't get stuck in infinite loop
    jobs[0].hash_hhh["program"]["x"].not_nil!.["pre-script"].should contain("b.milestones=y-ready")
    jobs[1].hash_hhh["program"]["y"].not_nil!.["pre-script"].should contain("a.milestones=x-ready")
  end

  it "handles jobs without dependencies" do
    job = MockJob.new.tap do |j|
      j.id = "indie"
      j.hash_hhh["program"]["app"] = {"if-role" => "standalone"}
    end
    jobid2roles = {"indie" => "standalone"}

    Cluster.cluster_depends2scripts([job], jobid2roles)

    job.hash_hhh["program"]["app"].not_nil!.["pre-script"]?.should be_nil
    job.hash_hhh["program"]["app"].not_nil!.["post-script"]?.should be_nil
  end

  it "handles missing dependency implementations" do
    job = MockJob.new.tap do |j|
      j.id = "orphan"
      j.hash_hhh["program"]["app"] = {
        "depends-on" => "missing",
        "if-role" => "test"
      }
    end
    jobid2roles = {"orphan" => "test"}

    Cluster.cluster_depends2scripts([job], jobid2roles)

    job.hash_hhh["program"]["app"].not_nil!.["pre-script"]?.should be_nil
  end

  it "processes cross-component dependencies" do
    jobs = [
      MockJob.new.tap do |j|
        j.id = "api"
        j.hash_hhh["daemon"]["service"] = {"if-role" => "backend"}
      end,
      MockJob.new.tap do |j|
        j.id = "worker"
        j.hash_hhh["program"]["task"] = {
          "depends-on" => "service",
          "if-role" => "processing"
        }
      end
    ]
    jobid2roles = {"api" => "backend", "worker" => "processing"}

    Cluster.cluster_depends2scripts(jobs, jobid2roles)

    worker_pre = jobs[1].hash_hhh["program"]["task"].not_nil!.["pre-script"]
    worker_pre.should contain("wait-jobs.sh api.milestones=service-ready")
  end

  it "processes jobs with multiple components" do
    job = MockJob.new.tap do |j|
      j.id = "multi"
      j.hash_hhh["daemon"]["db"] = {
        "if-role" => "database",
        "post-script" => "cleanup"
      }
      j.hash_hhh["program"]["cli"] = {
        "depends-on" => "db",
        "if-role" => "tool"
      }
    end
    jobid2roles = {"multi" => "database,tool"}

    Cluster.cluster_depends2scripts([job], jobid2roles)

    db_post = job.hash_hhh["daemon"]["db"].not_nil!.["post-script"]
    db_post.should contain("cleanup\njobfile_append_var milestones=db-ready")

    cli_pre = job.hash_hhh["program"]["cli"].not_nil!.["pre-script"]
    cli_pre.should contain("wait-jobs.sh multi.milestones=db-ready")
  end

  it "handles role inheritance from multiple components" do
    job = MockJob.new.tap do |j|
      j.hash_hhh["daemon"]["auth"] = {"if-role" => "security"}
      j.hash_hhh["program"]["monitor"] = {"if-role" => "observability"}
    end
    jobid2roles = {"job1" => "security,observability"}

    Cluster.cluster_depends2scripts([job], jobid2roles)

    Cluster.get_roles(job).should eq(["security", "observability"])
  end
end

describe "cluster_depends2scripts" do
  test_cases = YAML.parse(File.read(__DIR__ + "/cluster_depends2scripts.yaml"))
  test_cases.as_h["test_cases"].as_a.each do |tc|
    tc = tc.as_h
    it tc["name"] do
      # Convert YAML input to Job objects
      jobs = tc["input"].as_h["jobs"].as_a.map { |j| build_job_from_yaml(j.as_h) }
      jobid2roles = yaml2hash(tc["input"].as_h["jobid2roles"])

      # Process dependencies
      Cluster.cluster_depends2scripts(jobs, jobid2roles)

      # Verify output matches expected
      jobs.each_with_index do |job, i|
        expected = tc["expected"]["jobs"][i]
        verify_job_components(job, expected)
      end
    end
  end
end

private def yaml2hash(yaml)
  h = Hash(String, String).new
  yaml.as_h.each do |k, v|
    h[k.as_s] = v.as_s
  end
  h
end

private def build_job_from_yaml(yaml)
  job = MockJob.new
  job.id = yaml["id"].as_s
  yaml["components"].as_h.each do |comp_type, components|
    components.as_h.each do |name, config|
      job.hash_hhh[comp_type.as_s][name.as_s] = yaml2hash(config)
    end
  end
  job
end

private def verify_job_components(actual_job, expected_yaml)
  expected_yaml["components"].as_h.each do |comp_type, components|
    components.as_h.each do |name, expected_config|
      actual_config = actual_job.hash_hhh[comp_type.as_s][name.as_s]

      next unless expected_config
      next unless expected_config.as_h?
      expected_config.as_h.each do |script_type, expected_value|
        next unless actual_config
        actual_value = actual_config[script_type]?.to_s.strip
        actual_value.should eq(expected_value.to_s.strip),
          "Mismatch in #{actual_job.to_json}\nexpect: #{expected_value}\nactual: #{actual_value}"
      end
    end
  end
end
