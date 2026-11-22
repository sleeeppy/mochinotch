SELECT request.runtime_request_id,
       substr(coalesce(json_extract(item.payload_json, '$.questions[0].question'),
                       json_extract(item.payload_json, '$.prompt'), ''), 1, 160)
FROM orchestration_v2_projection_runtime_requests AS request
JOIN orchestration_v2_projection_turn_items AS item
  ON item.thread_id = request.thread_id AND item.node_id = request.node_id
 AND json_extract(item.payload_json, '$.requestId') = request.runtime_request_id
JOIN orchestration_v2_projection_runs AS run ON run.run_id = item.run_id
WHERE request.status = 'pending' AND item.status = 'waiting' AND run.provider = 'codex'
  AND item.type IN ('user_input_request', 'approval_request')
ORDER BY request.created_at
