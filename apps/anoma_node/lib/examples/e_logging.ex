defmodule Anoma.Node.Examples.ELogging do
  alias Anoma.Node
  alias Node.Logging
  alias Node.Transaction.{Mempool, Storage}
  alias Node.Examples.ENode

  require Node.Event

  require ExUnit.Assertions
  import ExUnit.Assertions

  def check_tx_event(node_id \\ Node.example_random_id()) do
    ENode.start_node(node_id: node_id)
    table_name = Logging.table_name(node_id)

    :mnesia.subscribe({:table, table_name, :simple})

    tx_event("id 1", "back 1", "code 1", node_id)

    assert_receive(
      {:mnesia_table_event, {:write, {_, "id 1", {"back 1", "code 1"}}, _}},
      5000
    )

    assert {:atomic, [{^table_name, "id 1", {"back 1", "code 1"}}]} =
             :mnesia.transaction(fn ->
               :mnesia.read(table_name, "id 1")
             end)

    :mnesia.unsubscribe({:table, table_name, :simple})
  end

  def check_multiple_tx_events(node_id \\ Node.example_random_id()) do
    ENode.start_node(node_id: node_id)

    table_name = Logging.table_name(node_id)

    :mnesia.subscribe({:table, table_name, :simple})

    tx_event("id 1", "back 1", "code 1", node_id)
    tx_event("id 2", "back 2", "code 2", node_id)

    assert_receive(
      {:mnesia_table_event,
       {:write, {^table_name, "id 1", {"back 1", "code 1"}}, _}},
      5000
    )

    assert_receive(
      {:mnesia_table_event,
       {:write, {^table_name, "id 2", {"back 2", "code 2"}}, _}},
      5000
    )

    assert {:atomic, [{^table_name, "id 1", {"back 1", "code 1"}}]} =
             :mnesia.transaction(fn ->
               :mnesia.read(table_name, "id 1")
             end)

    assert {:atomic, [{^table_name, "id 2", {"back 2", "code 2"}}]} =
             :mnesia.transaction(fn ->
               :mnesia.read(table_name, "id 2")
             end)

    :mnesia.unsubscribe({:table, table_name, :simple})
  end

  ############################################################
  #                      Consensus event                     #
  ############################################################

  def check_consensus_event(
        node_id \\ Node.example_random_id()
        |> Base.url_encode64()
      ) do
    check_tx_event(node_id)
    table_name = Logging.table_name(node_id)

    :mnesia.subscribe({:table, table_name, :simple})

    consensus_event(["id 1"], node_id)

    assert_receive(
      {:mnesia_table_event,
       {:write, {^table_name, :consensus, [["id 1"]]}, _}},
      5000
    )

    :mnesia.unsubscribe({:table, table_name, :simple})

    assert {:atomic, [{^table_name, :consensus, [["id 1"]]}]} =
             :mnesia.transaction(fn ->
               :mnesia.read(table_name, :consensus)
             end)
  end

  def check_consensus_event_multiple(
        node_id \\ Node.example_random_id()
        |> Base.url_encode64()
      ) do
    check_multiple_tx_events(node_id)
    table_name = Logging.table_name(node_id)

    :mnesia.subscribe({:table, table_name, :simple})

    consensus_event(["id 1"], node_id)
    consensus_event(["id 2"], node_id)

    assert_receive(
      {:mnesia_table_event,
       {:write, {^table_name, :consensus, [["id 1"], ["id 2"]]}, _}},
      5000
    )

    :mnesia.unsubscribe({:table, table_name, :simple})

    assert {:atomic, [{^table_name, :consensus, [["id 1"], ["id 2"]]}]} =
             :mnesia.transaction(fn ->
               :mnesia.read(table_name, :consensus)
             end)
  end

  ############################################################
  #                         Block event                      #
  ############################################################

  def check_block_event(
        node_id \\ Node.example_random_id()
        |> Base.url_encode64()
      ) do
    check_consensus_event(node_id)
    table_name = Logging.table_name(node_id)

    :mnesia.subscribe({:table, table_name, :simple})

    block_event(["id 1"], 0, node_id)

    assert_receive(
      {:mnesia_table_event, {:delete, {^table_name, "id 1"}, _}},
      5000
    )

    :mnesia.unsubscribe({:table, table_name, :simple})

    assert {:atomic, [{^table_name, :consensus, []}]} =
             :mnesia.transaction(fn ->
               :mnesia.read(table_name, :consensus)
             end)

    assert {:atomic, []} =
             :mnesia.transaction(fn ->
               :mnesia.read(table_name, "id 1")
             end)
  end

  def check_block_event_multiple(
        node_id \\ Node.example_random_id()
        |> Base.url_encode64()
      ) do
    check_consensus_event_multiple(node_id)
    table_name = Logging.table_name(node_id)

    :mnesia.subscribe({:table, table_name, :simple})
    block_event(["id 1"], 0, node_id)

    assert_receive(
      {:mnesia_table_event, {:delete, {^table_name, "id 1"}, _}},
      5000
    )

    assert {:atomic, [{^table_name, :consensus, [["id 2"]]}]} =
             :mnesia.transaction(fn ->
               :mnesia.read(table_name, :consensus)
             end)

    assert {:atomic, []} =
             :mnesia.transaction(fn ->
               :mnesia.read(table_name, "id 1")
             end)

    block_event(["id 2"], 0, node_id)

    assert_receive(
      {:mnesia_table_event, {:delete, {^table_name, "id 2"}, _}},
      5000
    )

    :mnesia.unsubscribe({:table, table_name, :simple})

    assert {:atomic, [{^table_name, :consensus, []}]} =
             :mnesia.transaction(fn ->
               :mnesia.read(table_name, :consensus)
             end)

    assert {:atomic, []} =
             :mnesia.transaction(fn ->
               :mnesia.read(table_name, "id 2")
             end)
  end

  def check_block_event_leave_one_out(
        node_id \\ Node.example_random_id()
        |> Base.url_encode64()
      ) do
    check_consensus_event_multiple(node_id)
    table_name = Logging.table_name(node_id)

    :mnesia.subscribe({:table, table_name, :simple})
    block_event(["id 1"], 0, node_id)

    assert_receive(
      {:mnesia_table_event, {:delete, {^table_name, "id 1"}, _}},
      5000
    )

    :mnesia.unsubscribe({:table, table_name, :simple})

    assert {:atomic, [{^table_name, :consensus, [["id 2"]]}]} =
             :mnesia.transaction(fn ->
               :mnesia.read(table_name, :consensus)
             end)

    assert {:atomic, []} =
             :mnesia.transaction(fn ->
               :mnesia.read(table_name, "id 1")
             end)

    assert {:atomic, [{^table_name, "id 2", {"back 2", "code 2"}}]} =
             :mnesia.transaction(fn ->
               :mnesia.read(table_name, "id 2")
             end)
  end

  def replay_corrects_result(node_id \\ Node.example_random_id()) do
    replay_ensure_created_tables(node_id)
    table = Storage.blocks_table(node_id)

    :mnesia.transaction(fn ->
      :mnesia.write(
        {table, 0, [%Mempool.Tx{backend: :debug_bloblike, code: "code 1"}]}
      )
    end)

    write_consensus_leave_one_out(node_id)
    filter = [%Mempool.TxFilter{}]

    EventBroker.subscribe_me(filter)

    Logging.restart_with_replay(node_id)

    :ok =
      wait_for_tx(node_id, "id 2", "code 2")

    :error_tx =
      wait_for_tx(node_id, "id 1", "code 1")

    state = Anoma.Node.Registry.whereis(node_id, Mempool) |> :sys.get_state()
    nil = Map.get(state.transactions, "id 1")
    1 = state.round

    state
  end

  def replay_consensus_leave_one_out(node_id \\ Node.example_random_id()) do
    write_consensus_leave_one_out(node_id)
    replay_ensure_created_tables(node_id)

    filter = [%Mempool.TxFilter{}]

    EventBroker.subscribe_me(filter)

    Logging.restart_with_replay(node_id)

    :ok =
      wait_for_tx(node_id, "id 1", "code 1")

    :ok =
      wait_for_tx(node_id, "id 2", "code 2")

    :ok =
      wait_for_consensus(node_id, ["id 1"])

    Mempool.execute(node_id, ["id 2"])

    :ok =
      wait_for_consensus(node_id, ["id 2"])
  end

  def replay_several_consensus(node_id \\ Node.example_random_id()) do
    write_several_consensus(node_id)
    replay_ensure_created_tables(node_id)

    txfilter = [%Mempool.TxFilter{}]
    consensus_filter = [%Mempool.ConsensusFilter{}]

    EventBroker.subscribe_me(txfilter)
    EventBroker.subscribe_me(consensus_filter)

    Logging.restart_with_replay(node_id)

    :ok =
      wait_for_tx(node_id, "id 1", "code 1")

    :ok =
      wait_for_tx(node_id, "id 2", "code 2")

    :ok =
      wait_for_consensus(node_id, ["id 1"])

    :ok =
      wait_for_consensus(node_id, ["id 2"])
  end

  def replay_consensus_with_several_txs(node_id \\ Node.example_random_id()) do
    write_consensus_with_several_tx(node_id)
    replay_ensure_created_tables(node_id)

    txfilter = [%Mempool.TxFilter{}]
    consensus_filter = [%Mempool.ConsensusFilter{}]

    EventBroker.subscribe_me(txfilter)
    EventBroker.subscribe_me(consensus_filter)

    Logging.restart_with_replay(node_id)

    :ok =
      wait_for_tx(node_id, "id 1", "code 1")

    :ok =
      wait_for_tx(node_id, "id 2", "code 2")

    :ok =
      wait_for_consensus(node_id, ["id 1", "id 2"])
  end

  def replay_consensus(node_id \\ Node.example_random_id()) do
    write_consensus(node_id)
    replay_ensure_created_tables(node_id)

    txfilter = [%Mempool.TxFilter{}]
    consensus_filter = [%Mempool.ConsensusFilter{}]

    EventBroker.subscribe_me(txfilter)
    EventBroker.subscribe_me(consensus_filter)

    Logging.restart_with_replay(node_id)

    :ok =
      wait_for_tx(node_id, "id 1", "code 1")

    :ok =
      wait_for_consensus(node_id, ["id 1"])
  end

  def replay_several_txs(node_id \\ Node.example_random_id()) do
    write_several_tx(node_id)
    replay_ensure_created_tables(node_id)

    txfilter = [%Mempool.TxFilter{}]

    EventBroker.subscribe_me(txfilter)

    Logging.restart_with_replay(node_id)

    :ok =
      wait_for_tx(node_id, "id 1", "code 1")

    :ok =
      wait_for_tx(node_id, "id 2", "code 2")
  end

  def replay_tx(node_id \\ Node.example_random_id()) do
    write_tx(node_id)
    replay_ensure_created_tables(node_id)

    txfilter = [%Mempool.TxFilter{}]

    EventBroker.subscribe_me(txfilter)

    {:ok, _pid} = Logging.restart_with_replay(node_id)

    :ok =
      wait_for_tx(node_id, "id 1", "code 1")
  end

  defp write_consensus_leave_one_out(node_id) do
    table = write_several_tx(node_id)

    :mnesia.transaction(fn ->
      :mnesia.write({table, :consensus, [["id 1"]]})
    end)

    table
  end

  defp write_several_consensus(node_id) do
    table = write_several_tx(node_id)

    :mnesia.transaction(fn ->
      :mnesia.write({table, :consensus, [["id 1"], ["id 2"]]})
    end)

    table
  end

  defp write_consensus_with_several_tx(node_id) do
    table = write_several_tx(node_id)

    :mnesia.transaction(fn ->
      :mnesia.write({table, :consensus, [["id 1", "id 2"]]})
    end)

    table
  end

  def write_consensus(node_id) do
    table = write_tx(node_id)

    :mnesia.transaction(fn ->
      :mnesia.write({table, :consensus, [["id 1"]]})
    end)

    table
  end

  defp write_several_tx(node_id) do
    table = create_event_table(node_id)

    :mnesia.transaction(fn ->
      :mnesia.write({table, "id 1", {:debug_bloblike, "code 1"}})
      :mnesia.write({table, "id 2", {:debug_bloblike, "code 2"}})
    end)

    table
  end

  defp write_tx(node_id) do
    table = create_event_table(node_id)

    :mnesia.transaction(fn ->
      :mnesia.write({table, "id 1", {:debug_bloblike, "code 1"}})
    end)

    table
  end

  defp wait_for_consensus(node_id, consensus) do
    receive do
      %EventBroker.Event{
        body: %Node.Event{
          node_id: ^node_id,
          body: %Mempool.ConsensusEvent{
            order: ^consensus
          }
        }
      } ->
        :ok
    after
      1000 -> :error_consensus
    end
  end

  defp wait_for_tx(node_id, id, code) do
    receive do
      %EventBroker.Event{
        body: %Node.Event{
          node_id: ^node_id,
          body: %Mempool.TxEvent{
            id: ^id,
            tx: %Mempool.Tx{backend: _, code: ^code}
          }
        }
      } ->
        :ok
    after
      1000 -> :error_tx
    end
  end

  defp create_event_table(node_id) do
    table = Logging.table_name(node_id)
    :mnesia.create_table(table, attributes: [:type, :body])

    :mnesia.transaction(fn ->
      :mnesia.write({table, :round, -1})
    end)

    table
  end

  defp replay_ensure_created_tables(node_id) do
    block_table = Storage.blocks_table(node_id)
    values_table = Storage.values_table(node_id)
    updates_table = Storage.updates_table(node_id)

    :mnesia.create_table(values_table, attributes: [:key, :value])
    :mnesia.create_table(updates_table, attributes: [:key, :value])
    :mnesia.create_table(block_table, attributes: [:round, :block])

    [
      block_table: block_table,
      values_table: values_table,
      updates_table: updates_table
    ]
  end

  def tx_event(id, backend, code, node_id) do
    event =
      Node.Event.new_with_body(node_id, %Mempool.TxEvent{
        id: id,
        tx: %Mempool.Tx{backend: backend, code: code}
      })

    EventBroker.event(event)
  end

  def consensus_event(order, node_id) do
    event =
      Node.Event.new_with_body(node_id, %Mempool.ConsensusEvent{
        order: order
      })

    EventBroker.event(event)
  end

  def block_event(order, round, node_id) do
    event =
      Node.Event.new_with_body(node_id, %Mempool.BlockEvent{
        order: order,
        round: round
      })

    EventBroker.event(event)
  end
end
