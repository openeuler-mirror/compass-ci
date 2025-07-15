import os

class Config:
    PORT = int(os.environ.get('BISECT_API_PORT', 9999))
    MANTICORE_HOST = os.environ.get('MANTICORE_HOST', 'localhost')
    MANTICORE_PORT = int(os.environ.get('MANTICORE_PORT', 9306))
    MANTICORE_WRITE_PORT = int(os.environ.get('MANTICORE_WRITE_PORT', 9308))
    BISECT_MODE = os.environ.get('bisect_mode', 'local')
    LKP_SRC = os.environ.get('LKP_SRC', '/lkp/lkp')
    CCI_SRC = os.environ.get('CCI_SRC', '/cci')
