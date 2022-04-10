extends Node3D

const RPC_PORT := 50000
const UDP_PORT := 50001

var client_start_frame : int = 0
var client_peer : int = -1
var udp_server : UDPServer = null
var udp_client : PacketPeerUDP = null
var udp_peer : PacketPeerUDP = null

@onready var label_rpc = $LabelRPC
@onready var label_udp = $LabelUDP
@onready var rpc_latency_min := 999999
@onready var rpc_latency_max := 0
@onready var udp_latency_min := 999999
@onready var udp_latency_max := 0


func _ready():
    var peer := ENetMultiplayerPeer.new()
    if "--server" in OS.get_cmdline_args():
        peer.create_server(RPC_PORT)
        udp_server = UDPServer.new()
        udp_server.listen(UDP_PORT)
        $LabelPeer.text = "server"
    else:
        peer.create_client("127.0.0.1", RPC_PORT)
        udp_client = PacketPeerUDP.new()
        udp_client.connect_to_host("127.0.0.1", UDP_PORT)
        $LabelPeer.text = "client"

    multiplayer.set_multiplayer_peer(peer)

    $HSlider.connect("value_changed", _set_target_fps)
    _set_target_fps(60)


func _physics_process(delta):
    _physics_process_rpc_method(delta)
    _physics_process_udp_method(delta)


func _physics_process_rpc_method(delta):
    if is_multiplayer_authority():
        # should have already gotten some client input via rpc and stuck it in a var

        # TODO do authoritative movement here

        # Update client with new authoritative state of the world.
        # Send back the start frame so they know which input frame
        # was used to generate it on their side.
        if client_peer >= 0:
            update_client.rpc_id(client_peer, client_start_frame)
    else:
        # send input to server via rpc
        update_server.rpc_id(get_multiplayer_authority(), Engine.get_physics_frames())

        # TODO movement and client side prediction here using info from server
        # (should have got some server updates via rpc and stored them in some vars)

        if client_start_frame > 0:
            var frame_round_trip_delay := Engine.get_physics_frames() - client_start_frame
            var frame_round_trip_ms = frame_round_trip_delay * delta * 1000
            rpc_latency_max = max(rpc_latency_max, frame_round_trip_delay)
            rpc_latency_min = min(rpc_latency_min, frame_round_trip_delay)
            var ticks = "".rpad(frame_round_trip_delay, "*")
            label_rpc.text = "rpc round trip %2d physics ticks (%4.1f ms)\nmin %2d max %2d\n%s" % [
                frame_round_trip_delay, frame_round_trip_ms, rpc_latency_min, rpc_latency_max, ticks]


func _physics_process_udp_method(delta):
    if udp_server != null:
        var start_frame := recieve_from_client_udp()

        # TODO do authoritative movement here

        # Update client with new authoritative state of the world.
        # Send back the start frame so they know which input frame
        # was used to generate it on their side.
        send_to_client_udp(start_frame)
    else:
        # send input to server via udp
        send_to_server_udp(Engine.get_physics_frames())

        # get servers authoritative state of the world
        var start_frame := recieve_from_server_udp()

        # TODO movement and client side prediction here using info from server

        if start_frame > 0:
            var frame_round_trip_delay := Engine.get_physics_frames() - start_frame
            var frame_round_trip_ms = frame_round_trip_delay * delta * 1000
            udp_latency_max = max(udp_latency_max, frame_round_trip_delay)
            udp_latency_min = min(udp_latency_min, frame_round_trip_delay)
            var ticks = "".lpad(frame_round_trip_delay, "*")
            label_udp.text = "udp round trip %2d physics ticks (%4.1f ms)\nmin %2d max %2d\n%s" % [
                frame_round_trip_delay, frame_round_trip_ms, udp_latency_min, udp_latency_max, ticks]


@rpc(unreliable, any_peer)
func update_server(start_frame : int):
    client_peer = multiplayer.get_remote_sender_id()
    client_start_frame = max(start_frame, client_start_frame)


@rpc(unreliable, any_peer)
func update_client(start_frame : int):
    client_start_frame = max(start_frame, client_start_frame)


func send_to_server_udp(start_frame : int):
    var packet := PackedByteArray()
    packet.resize(8)
    packet.encode_s64(0, start_frame)
    udp_client.put_packet(packet)


func recieve_from_client_udp() -> int:
    udp_server.poll()
    if udp_server.is_connection_available():
        udp_peer = udp_server.take_connection()

    var frame := 0
    if udp_peer != null:
        for _ignored in range(udp_peer.get_available_packet_count()):
            frame = max(frame, udp_peer.get_packet().decode_s64(0))

    return frame


func send_to_client_udp(start_frame : int):
    if udp_peer == null:
        return

    var packet = PackedByteArray()
    packet.resize(8)
    packet.encode_s64(0, start_frame)
    udp_peer.put_packet(packet)


func recieve_from_server_udp() -> int:
    var frame := 0
    for _ignored in range(udp_client.get_available_packet_count()):
        frame = max(frame, udp_client.get_packet().decode_s64(0))

    return frame


func _set_target_fps(target):
    Engine.target_fps = target
    $LabelTargetFPS.text = "%s" % Engine.target_fps
