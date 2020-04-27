require "spec"

require "../../src/scheduler/qos"

describe Scheduler::Qos do

    describe "1 queue, 10000 jobs" do
        it "initialize with  1 queue and 10000 token" do
            qos = Scheduler::Qos.new(1, 10000)
            qos.queueTokenNum(0).should eq(10000)
        end

        it "Cycle update token in 100ms" do
            qos = Scheduler::Qos.new(1, 10000)
            qos.queueTokenGet(0)
            qos.queueTokenNum(0).should eq(9999)
            sleep(Time::Span.new(nanoseconds: 200_000_000) ) # sleep 200ms
            qos.queueTokenNum(0).should eq(10000)
            qos.queueTokenGet(0)
            qos.queueTokenNum(0).should eq(9999)
            sleep(Time::Span.new(nanoseconds: 200_000_000) )
            qos.queueTokenNum(0).should eq(10000)
        end
    end

    describe "2 queue, 5000 jobs" do
        it "initialize with 2 queue and 5000 token" do
            qos = Scheduler::Qos.new(2, 5000)
            qos.queueTokenNum(0).should eq(3090)
            qos.queueTokenNum(1).should eq(1910)
        end

        it "Cycle update token in 100ms" do
            qos = Scheduler::Qos.new(2, 5000)
            qos.queueTokenGet(0)
            qos.queueTokenGet(1)
            sleep(Time::Span.new(nanoseconds: 200_000_000) ) # sleep 200ms
            qos.queueTokenNum(0).should eq(3090)
            qos.queueTokenNum(1).should eq(1910)
        end

        it "First order  can configured" do
            qos = Scheduler::Qos.new(2, 5000)
            qos.configurePriority(1)
            qos.resetToken()
            qos.queueTokenNum(0).should eq(1910)
            qos.queueTokenNum(1).should eq(3090)
        end
    end

    describe "queue name translate" do
        it "match translate" do
            qos = Scheduler::Qos.new(2, 5000)
            qos.queueNameTranslate("First").should eq(0)
            qos.queueNameTranslate("Second").should eq(1)
            qos.queueNameTranslate("Third").should eq(1)
        end

        it "unmatch translate" do
            qos = Scheduler::Qos.new(2, 5000)
            qos.queueNameTranslate("Third").should eq(1)
            qos.queueNameTranslate("What else").should eq(1)
        end
    end
end