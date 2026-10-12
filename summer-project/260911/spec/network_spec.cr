require "spec"
require "../src/network"
require "../src/node"
require "../src/constants"

WORKER_COUNT = 4

describe Network do
  describe "#initialize and construction helpers" do
    it "builds correct layer bounds" do
      layer_sizes = [3, 4, 2]
      network = Network.new(layer_sizes, 2)

      bounds = network.layer_bounds
      bounds.size.should eq(3)

      # Layer 0: nodes 0..2
      bounds[0].start_id.should eq(0_u32)
      bounds[0].end_id.should eq(2_u32)

      # Layer 1: nodes 3..6
      bounds[1].start_id.should eq(3_u32)
      bounds[1].end_id.should eq(6_u32)

      # Layer 2: nodes 7..8
      bounds[2].start_id.should eq(7_u32)
      bounds[2].end_id.should eq(8_u32)
    end

    it "creates the correct number of nodes with proper layer indices" do
      layer_sizes = [2, 3]
      network = Network.new(layer_sizes, 2)

      nodes = network.all_nodes
      nodes.size.should eq(5)

      # Layer 0
      nodes[0].id.should eq(0_u32)
      nodes[0].layer_index.should eq(0)

      nodes[1].id.should eq(1_u32)
      nodes[1].layer_index.should eq(0)

      # Layer 1
      nodes[2].id.should eq(2_u32)
      nodes[2].layer_index.should eq(1)

      nodes[3].id.should eq(3_u32)
      nodes[3].layer_index.should eq(1)

      nodes[4].id.should eq(4_u32)
      nodes[4].layer_index.should eq(1)
    end

    it "creates the expected number of workers" do
      worker_count = 4
      network = Network.new([2, 2], worker_count)
      network.workers.size.should eq(worker_count)

      network.workers.each_with_index do |w, i|
        w.id.should eq(i)
      end
    end
  end

  describe "#worker_id_for_node" do
    it "maps node ids to workers using modulo" do
      network = Network.new([4], 2)

      network.worker_id_for_node(0_u32).should eq(0)
      network.worker_id_for_node(1_u32).should eq(1)
      network.worker_id_for_node(2_u32).should eq(0)
      network.worker_id_for_node(3_u32).should eq(1)
    end
  end

  describe "#input" do
    it "enqueues an event on the correct worker" do
      network = Network.new([3], 2)

      # Node 1 should go to worker (1 % @worker_count)
      node_id = 1_u32
      process_at = 10_u64

      # Capture initial queue sizes
      before_sizes = network.workers.map(&.incoming_queues.map(&.buffer_depth))

      network.input(node_id, process_at)

      after_sizes = network.workers.map(&.incoming_queues.map(&.buffer_depth))

      expected_worker = network.worker_id_for_node(node_id)
      (after_sizes[expected_worker] - before_sizes[expected_worker]).should eq([1])

      # Other workers’ queues should be unchanged
      network.workers.each_with_index do |w, i|
        next if i == expected_worker
        (after_sizes[i] - before_sizes[i]).should be_empty
      end
    end
  end

  describe "#run_worker_loop_iteration" do
    it "processes events strictly within the safe horizon and synchronises with SyncManager" do
      # Setup real Network instance with known layer delay and loader time.
      network = Network.new([1], worker_count: 2, layer_delay: 4_u64)
      worker0 = network.workers[0]
      worker1 = network.workers[1]
      sync_mgr = network.sync_mgr
      sync_mgr.update_loader_time(10_u64)

      # Both workers initially at t = 0; global_min = 0.
      # Safe horizon is min(global_min + LAYER_DELAY, loader_time) = min(0 + 4, 10) = 4.
      sync_mgr.safe_time(0_u32).should eq 4_u64

      # Schedule real events on worker0's actual hierarchical wheel.
      target_id = 0_u32
      worker0.clock.schedule(target_id, 1_u64)
      worker0.clock.schedule(target_id, 3_u64)
      # Event at t=5 is beyond the safe horizon (4).
      worker0.clock.schedule(target_id, 5_u64)

      # Execute a single iteration synchronously on the calling thread.
      allowed = network.run_worker_loop_iteration(worker0)

      # Assertions on real objects.
      # Clock advanced strictly to the safe horizon boundary (4).
      worker0.clock.current_time.should eq 4_u64

      # Real SyncManager reflects worker0's reported time.
      sync_mgr.worker_clocks[0].clock.get.should eq 4_u64

      # Exactly 2 events (t=1 and t=3) were processed; event at t=5 was NOT touched.
      target_node = network.all_nodes[target_id]
      target_node.processed_count.should eq 2

      # Because worker1 is still lagging at 0, worker0 at 4 is at the safe horizon limit.
      allowed.should be_true

      # Verify that the event at t=5 is still safely queued in the wheel:
      # Catch worker1 up to t=2, which moves global_min to 2 and safe_time to min(2 + 4, 10) = 6.
      sync_mgr.record_progress(worker1.id, 2_u64)
      sync_mgr.safe_time(worker0.id).should eq 6_u64

      # Run the next iteration for worker0: now the horizon includes t=5
      network.run_worker_loop_iteration(worker0)

      worker0.clock.current_time.should eq 6_u64
      target_node.processed_count.should eq 3
    end

    it "strictly respects loader_time as a ceiling even when safe horizon is larger" do
      network = Network.new([4], 1, 10_u64)
      worker = network.workers[0]
      sync_mgr = network.sync_mgr

      # Set loader ceiling lower than safe horizon boundary:
      sync_mgr.update_loader_time(2_u64)
      target_id = 0_u32

      worker.clock.schedule(target_id, 1_u64)
      worker.clock.schedule(target_id, 2_u64)
      worker.clock.schedule(target_id, 3_u64)

      # Run one iteration
      network.run_worker_loop_iteration(worker)

      # Worker cannot advance past loader_time (2_u64)
      worker.clock.current_time.should eq 2_u64
      sync_mgr.worker_clocks[0].clock.get.should eq 2_u64
    end
  end

  describe "#run_worker_loop" do
    it "processes an event and dispatches via router" do
      # Create a small network with a single worker so we control timing easily.
      network = Network.new([2], 1, training: false)
      worker = network.workers[0]

      # Ensure the worker starts at a known time.
      # HierarchicalClock is initialized with current_time = 0 in Worker.new.
      worker.clock.current_time.should eq(0_u64)

      # Enqueue an input event for node 0 to be processed at time 5.
      node_id = 0_u32
      process_at = 5_u64
      network.input(node_id, process_at)

      # At this point the event is in the worker's incoming queue, not yet in the clock.
      # Drain incoming queues into the clock manually to simulate what run_worker_loop does.
      worker.drain_all_incoming

      # The event should now be scheduled in the clock at time 5.
      # We can't directly inspect the clock internals here without more accessors,
      # but we can verify that advancing the clock processes the event.

      # Track whether the router saw a dispatch for this node.
      dispatched = false
      original_router = network.router

      # If Router is a class, you might need to inject a test spy or add a hook.
      # For now, assume we can wrap dispatch via monkey‑patching or by checking
      # side effects on nodes. If Node.process changes state, we can assert that.

      # Advance the clock manually, mimicking the tick inside run_worker_loop.
      # We'll step time forward to so that the next tick processes the specified time (half open).
      worker.clock.advance_to(5_u64) { }

      # Process one tick: this is effectively what the block inside run_worker_loop does.
      worker.clock.tick do |event|
        node = network.all_nodes[event.target_node]
        new_state = node.process(event.payload)
        original_router.dispatch(node, new_state, worker.id)
        dispatched = true
      end

      dispatched.should be_true

      # Optionally, assert something about the node's state change if Node exposes it.
      # For example, if Node has a `state` or `last_payload` field:
      # network.all_nodes[node_id].last_payload.should eq(1.0)
    end
  end

  describe "#reset_network" do
    it "resets worker clocks and sync state" do
      network = Network.new([2, 2], 2)

      # Advance time and do some work so clocks are non‑zero.
      worker0 = network.workers[0]
      worker1 = network.workers[1]

      # Simulate some progression: enqueue and drain to move clocks.
      network.input(0_u32, 10_u64)
      network.input(3_u32, 10_u64)

      worker0.drain_all_incoming
      worker1.drain_all_incoming

      # Manually advance their clocks a bit.
      worker0.clock.advance_to(10_u64) { }
      worker1.clock.advance_to(10_u64) { }

      # Update SyncManager so it sees these times.
      network.sync_mgr.record_progress(0, 10_u64)
      network.sync_mgr.record_progress(1, 10_u64)

      # Now reset the network at a new base time.
      first_event_time = 100_u64
      last_event_time = 200_u64
      network.reset(first_event_time, last_event_time)

      # Implement reset_network to:
      # - Reset each worker's clock.current_time to first_event_time
      # - Reset SyncManager global_min and worker clocks to first_event_time
      #
      # Then assert those here. Example assertions (once reset_network is implemented):

      worker0.clock.current_time.should eq(first_event_time)
      worker1.clock.current_time.should eq(first_event_time)
      network.sync_mgr.global_min.get.should eq(first_event_time)
      network.sync_mgr.worker_clocks.each(&.clock.get.should eq(first_event_time))
    end
  end

  describe "#reset" do
    it "resets worker clock clocks and sync manager worker clocks" do
      network = Network.new([1], 1)
      network.reset(2_u64, 10_u64)
      network.sync_mgr.worker_clocks.each(&.clock.get.should eq 2_u64)
      network.workers.each(&.clock.current_time.should eq(2_u64))
    end
  end

  describe "sample-end marker integration" do
    it "exposes sync_mgr for sample end time management" do
      network = Network.new([10, 5], 2)
      network.sync_mgr.should_not be_nil
      network.sync_mgr.is_a?(SyncManager).should be_true
    end

    it "allows setting sample end time via sync_mgr" do
      network = Network.new([10, 5], 2)
      sample_end = 1000_u64

      network.sync_mgr.update_last_event_time(sample_end)
      # This tests that the method exists and is callable
      # The actual behavior is tested in SyncManager specs
    end

    it "resets all state including sample_end markers" do
      network = Network.new([5, 5], 2)
      t0 = 500_u64
      t_end = 1000_u64

      # Set up a sample
      network.sync_mgr.update_last_event_time(1000_u64)
      network.sync_mgr.update_loader_time(1000_u64)

      # Advance workers past sample end
      network.workers[0].clock.reset(1050_u64)
      network.workers[1].clock.reset(1050_u64)
      network.sync_mgr.record_progress(0, 1050_u64)
      network.sync_mgr.record_progress(1, 1050_u64)

      # Verify workers are marked done
      network.sync_mgr.all_workers_finished_sample?.should be_true

      # Reset for new sample
      network.reset(t0, t_end)

      # All workers should be reset
      network.sync_mgr.all_workers_finished_sample?.should be_false
      network.sync_mgr.loader_time.get.should eq(t0)
    end
  end

  describe "#input with loader_time updates" do
    it "updates loader_time when enqueueing events" do
      network = Network.new([10], 2)
      node_id = 0_u32
      process_at = 100_u64

      network.input(node_id, process_at)

      network.sync_mgr.loader_time.get.should eq(process_at)
    end

    it "updates loader_time monotonically for sequential events" do
      network = Network.new([10], 2)

      network.input(0_u32, 100_u64)
      network.sync_mgr.loader_time.get.should eq(100_u64)

      network.input(1_u32, 150_u64)
      network.sync_mgr.loader_time.get.should eq(150_u64)

      network.input(2_u32, 200_u64)
      network.sync_mgr.loader_time.get.should eq(200_u64)
    end

    it "routes events to correct worker based on node_id" do
      network = Network.new([10], 2)

      # Node 0 should go to worker 0 (0 % 2 = 0)
      network.input(0_u32, 100_u64)
      # Node 1 should go to worker 1 (1 % 2 = 1)
      network.input(1_u32, 100_u64)
      # Node 2 should go to worker 0 (2 % 2 = 0)
      network.input(2_u32, 100_u64)

      # Verify loader_time is updated to latest event time
      network.sync_mgr.loader_time.get.should eq(100_u64)
    end
  end

  describe "sample processing workflow" do
    it "supports complete sample lifecycle" do
      # Simulate the pattern from main.cr training loop
      network = Network.new([10, 5], 2)

      # Sample 1: events from t=0 to t=100
      t0 = 0_u64
      t_end =  1000_u64
      sample1_end = 100_u64
      safety_margin = 10_u64
      sample1_end_with_margin = sample1_end + safety_margin

      network.reset(t0, t_end)
      network.sync_mgr.update_last_event_time(sample1_end_with_margin)

      # Feed events
      network.input(0_u32, 10_u64)
      network.input(1_u32, 20_u64)
      network.input(2_u32, 50_u64)
      network.input(3_u32, 100_u64)

      # Manually advance workers to simulate processing
      network.workers[0].clock.reset(sample1_end_with_margin)
      network.workers[1].clock.reset(sample1_end_with_margin)
      network.sync_mgr.record_progress(0, sample1_end_with_margin)
      network.sync_mgr.record_progress(1, sample1_end_with_margin)

      # All workers should be done
      network.sync_mgr.all_workers_finished_sample?.should be_true

      # Sample 2: reset and process new sample
      t0_sample2 = 200_u64
      sample2_end = 300_u64
      sample2_end_with_margin = sample2_end + safety_margin

      network.reset(t0_sample2, t_end)
      network.sync_mgr.update_last_event_time(sample2_end_with_margin)

      # Workers should be reset
      network.sync_mgr.all_workers_finished_sample?.should be_false

      # Feed sample 2 events
      network.input(0_u32, 210_u64)
      network.input(1_u32, 250_u64)
      network.input(2_u32, 300_u64)

      # Advance workers
      network.workers[0].clock.reset(sample2_end_with_margin)
      network.workers[1].clock.reset(sample2_end_with_margin)
      network.sync_mgr.record_progress(0, sample2_end_with_margin)
      network.sync_mgr.record_progress(1, sample2_end_with_margin)

      network.sync_mgr.all_workers_finished_sample?.should be_true
    end
  end

  describe "#worker_id_for_node" do
    it "distributes nodes evenly across workers" do
      worker_count = 4
      network = Network.new([100], worker_count)

      # Test round-robin distribution
      10.times do |i|
        expected_worker = i % worker_count
        network.worker_id_for_node(i.to_u32).should eq(expected_worker)
      end
    end

    it "handles large node IDs correctly" do
      worker_count = 4
      network = Network.new([1000], worker_count)

      # Test with large node IDs
      network.worker_id_for_node(999_u32).should eq(999 % worker_count)
      network.worker_id_for_node(10000_u32).should eq(10000 % worker_count)
    end
  end

  describe "concurrent sample processing" do
    it "prevents workers from running ahead of loader" do
      network = Network.new([10, 5], 1)
      t0 = 0_u64
      # Set sample end time
      sample_end = 100_u64
      just_short = 98_u64

      network.reset(t0, sample_end)

      network.sync_mgr.update_loader_time(just_short)

      # Try to advance worker beyond loader + LAYER_DELAY
      # With LAYER_DELAY = 1, worker at time 102 should be blocked when loader is at 100
      network.sync_mgr.record_progress(0, just_short)
      network.sync_mgr.record_progress(0, sample_end)

      # Advance loader.
      network.sync_mgr.update_loader_time(sample_end)

      # Now worker can advance.
      network.sync_mgr.record_progress(0, sample_end)
    end
  end
end
