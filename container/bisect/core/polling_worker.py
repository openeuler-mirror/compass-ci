#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
PollingWorker base class for database-polling background threads.

Encapsulates the common poll → backoff → process → wait pattern used by
BisectConsumer and SuccessTaskValidator, eliminating duplicated loop
boilerplate.

Usage:
    class MyWorker(PollingWorker):
        def setup(self):
            # one-time initialization (called before loop starts)
            ...

        def process_cycle(self) -> bool:
            # do work, return True if work was found
            ...

    worker = MyWorker("MyWorker", stop_event, base_interval=30)
    threading.Thread(target=worker.run, daemon=True).start()
"""

import time
import threading
import traceback
from log_config import logger


class PollingWorker:
    """
    Base class for polling-based background workers.

    Subclasses implement:
        setup()          — optional one-time init before the loop
        process_cycle()  — returns True if work was done, False otherwise

    The base class handles:
        - Exponential backoff when idle
        - Immediate wake on stop_event
        - Consistent logging
    """

    def __init__(self, name: str, stop_event: threading.Event,
                 base_interval: float = 30, max_backoff: float = 300,
                 wake_event: threading.Event = None):
        self.name = name
        self.stop_event = stop_event
        self.base_interval = base_interval
        self.max_backoff = max_backoff
        self.wake_event = wake_event  # optional: external signal to wake early

    @property
    def running(self) -> bool:
        return not self.stop_event.is_set()

    def setup(self):
        """Optional one-time initialization. Override in subclass."""
        pass

    def process_cycle(self) -> bool:
        """
        Execute one polling cycle.

        Returns True if work was found/processed, False if idle.
        Raise exceptions freely — the base loop catches and logs them.
        """
        raise NotImplementedError

    def run(self):
        """Main loop — call this as the thread target."""
        current_thread = threading.current_thread()
        logger.info(f"{self.name} started in thread {current_thread.name}")

        try:
            self.setup()
        except Exception as e:
            logger.error(f"{self.name} setup failed: {e}")
            logger.error(traceback.format_exc())
            return

        consecutive_empty = 0

        while self.running:
            start_time = time.time()
            logger.debug(f"{self.name} cycle starting...")

            try:
                had_work = self.process_cycle()

                if had_work:
                    consecutive_empty = 0
                    cycle_time = time.time() - start_time
                    wait = max(self.base_interval * 0.5, self.base_interval - cycle_time)
                else:
                    consecutive_empty += 1
                    wait = min(self.base_interval * (2 ** consecutive_empty), self.max_backoff)
                    logger.debug(f"{self.name} idle, backing off {wait:.0f}s (round {consecutive_empty})")

            except Exception as e:
                logger.error(f"{self.name} cycle error: {e}")
                logger.error(traceback.format_exc())
                consecutive_empty += 1
                wait = min(self.base_interval * (2 ** consecutive_empty), self.max_backoff)

            # Wait for timeout, stop signal, or external wake
            if self.wake_event:
                # Wait on whichever fires first: stop or wake
                # We can't wait on two events natively, so poll with short intervals
                # or use the wake_event as a secondary check
                self.wake_event.clear()
                # Use stop_event.wait but check wake_event periodically
                remaining = wait
                while remaining > 0 and not self.stop_event.is_set():
                    chunk = min(remaining, 5.0)
                    self.stop_event.wait(chunk)
                    if self.wake_event.is_set():
                        self.wake_event.clear()
                        logger.info(f"{self.name} woken by external event, resuming immediately")
                        break
                    remaining -= chunk
            else:
                self.stop_event.wait(wait)

        logger.info(f"{self.name} loop exited")
