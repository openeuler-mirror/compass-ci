# 1.Promise rate control  10000(job token)/s
# 3.timely fill token (when all token is empty)
# 3.N queues with priority configurable

module Scheduler
    class Qos

        @queueArray = [] of Int32
        @queuePriority = [] of Int32
        @queueMax = [] of Int32
        @queueCycleAdd = [] of Int32

        def initialize(queueNum : Int32, promiseRate : Int32)
            @queueNum = queueNum
            @promiseRate = promiseRate

            @previousGetJobQueueID = 0

            assignToken()
            startUpdateTokenProcess()
        end

        def assignToken()
            tokenLeft = @promiseRate
            @queueNum.times do |index|
                tokenAssign = (tokenLeft * 0.618).to_i
                @queueArray << tokenAssign

                @queuePriority << index

                tokenLeft =  tokenLeft - tokenAssign
            end
            @queueArray[@queueNum - 1] = @queueArray[@queueNum - 1]  + tokenLeft

            @queueNum.times do |index|
                total = @queueArray[index]
                @queueMax << total
                @queueCycleAdd << (total/10).to_i
            end
        end

        def resetToken()
            tokenLeft = @promiseRate
            @queueNum.times do |index|
                tokenAssign = (tokenLeft * 0.618).to_i
                @queueArray[@queuePriority[index]] = tokenAssign
                tokenLeft =  tokenLeft - tokenAssign
            end
            @queueArray[@queuePriority[@queueNum - 1]] = @queueArray[@queuePriority[@queueNum - 1]]  + tokenLeft
        end

        def cycleAddToken()
            @queueNum.times do |index|
                @queueArray[@queuePriority[index]] = @queueArray[@queuePriority[index]] + @queueCycleAdd[index]
                if @queueArray[@queuePriority[index]] > @queueMax[index]
                    @queueArray[@queuePriority[index]] = @queueMax[index]
                end
            end
        end

        def timeJob()
            loop do
                sleep(Time::Span.new(nanoseconds: 100_000_000) )
                cycleAddToken()
            end
        end

        # ? conflict with queueTokenGet
        def startUpdateTokenProcess()
            spawn do
                Process.new(timeJob)
            end
        end

        def queueTokenGet(queueID : Int32)
            if (queueID < 0) || (queueID >= @queueNum)
                return 0
            end

            if @queueArray[queueID] >0
                @queueArray[queueID] = @queueArray[queueID] - 1
                return 1
            else
                return 0
            end
        end

        def queueTokenNum(queueName : String)
            return queueTokenNum(queueNameTranslate(queueName))
        end

        # queueID:
        #  i = [0, @queueNum - 1] : @queueArray[i]
        #  = @queueArray[@queueNum - 1]
        def queueTokenNum(queueID : Int32)
            hasToken = 0

            if queueID < @queueNum &&  queueID >= 0
                hasToken = @queueArray[queueID]
            end

            return hasToken
        end

        def configurePriority( firstOrder : Int32)
            if firstOrder < @queueNum
                firstOrder.times do |index|
                    @queuePriority[firstOrder - index] = @queuePriority[firstOrder - index - 1]
                end
                @queuePriority[0] = firstOrder
                return 1
            else
                return 0
            end
        end

        def queueNameTranslate(queue_name : String)

            # default use the lowest priority queue
            defaultQueueID = @queuePriority[@queueNum - 1]
            matchedQueueID = defaultQueueID

            case queue_name.downcase
            when "first"         # first queue is "sorted_job_list_0"
                matchedQueueID = 0
            when "second"
                matchedQueueID = 1
            when "thrid"
                matchedQueueID = 2
            when "fourth"
                matchedQueueID = 3
            else
                # do nothing
            end

            if matchedQueueID >= @queueNum
                matchedQueueID = defaultQueueID
            end

            return matchedQueueID
        end

        def switchtoNextQueue()
            @previousGetJobQueueID = (@previousGetJobQueueID + 1) % @queueNum
        end

    end
end