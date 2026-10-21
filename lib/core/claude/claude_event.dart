/// Compatibility export for persisted Claude events and existing callers.
library;

import '../providers/agent_event.dart';
export '../providers/agent_event.dart';

typedef ClaudeEvent = AgentEvent;
