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
        - Immediate wake on stop_event or external wake signal
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

        # Condition + flag: unifies stop + wake into a single wait point.
        # _should_wake is set by the listener thread when wake_event fires,
        # so wait_for returns immediately instead of polling every 5s.
        self._cond = threading.Condition(threading.Lock())
        self._should_wake = False

        if self.wake_event:
            self._wake_listener = threading.Thread(
                target=self._watch_wake_event,
                daemon=True,
                name=f"{name}-wake-listener"
            )
        else:
            self._wake_listener = None

    def _watch_wake_event(self):
        """Listener thread: waits on wake_event and forwards to _cond."""
        while not self.stop_event.is_set():
            if self.wake_event.wait(timeout=30):
                self.wake_event.clear()
                with self._cond:
                    self._should_wake = True
                    self._cond.notify_all()

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

        # Start wake listener if wake_event is configured
        if self._wake_listener:
            self._wake_listener.start()

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

            # Wait for timeout, stop signal, or external wake — all via _cond
            with self._cond:
                self._should_wake = False
                self._cond.wait_for(
                    lambda: self.stop_event.is_set() or self._should_wake,
                    timeout=wait
                )

                if self._should_wake:
                    self._should_wake = False
                    logger.info(f"{self.name} woken by external event, resuming immediately")

            if not self.running:
                break

        logger.info(f"{self.name} loop exited")
