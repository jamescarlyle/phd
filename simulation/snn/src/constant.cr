MICROSECONDS_PER_MS     = 1_000_u64
MS_PER_SECOND           = 1_000_u64
MICROSECONDS_PER_SECOND = 1_000_000_u64
SAMPLE_CAPACITY         = 4
TRAIN_DATA              = "../snn/data/Train"
TEST_DATA               = "../snn/data/Test"
LAYER_LATENCY           = 2_000_u64
MAX_DRIFT               = 1_000_u64
LOADER_COUNT            = 1u32
NETWORK_TYPE            = "lif"
DATASET_TYPE            = "mnist"
LAYER_SIZES             = [2312_u16, 10_u16]
TRAIN_COUNT             = 1u32
TEST_COUNT              = 1u32
BUFFER_CAPACITY         = 2u32 ** 12 # 512/32 works for 2312/100/10 2**12/2**4 works for 2312,100,100
LEVEL1_SCALE            = 2u8 ** 4

MAX_NODES_PER_LAYER_SHIFT = 12_u32
MAX_NODES_PER_LAYER       = 1_u32 << MAX_NODES_PER_LAYER_SHIFT
MAX_NODES_PER_LAYER_MASK  = MAX_NODES_PER_LAYER - 1_u32

MAX_WORKERS_SHIFT       = 2_u8                                    # 2 - better for Mac Air M4, but specs need 3 (8 workers)
MAX_WORKERS             = 1_u8 << MAX_WORKERS_SHIFT               # 00000100 = 4
MAX_WORKERS_MASK        = MAX_WORKERS - 1_u8                      # 00001111

LOCAL_NODE_INDEX_BITS = 16
LOCAL_NODE_INDEX_MASK = 0xffff_u32
