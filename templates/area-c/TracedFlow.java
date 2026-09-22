package @@PACKAGE@@;

import static io.quarkiverse.flow.dsl.FlowDSL.function;

import java.util.HashMap;
import java.util.Map;

import jakarta.enterprise.context.ApplicationScoped;

import io.quarkiverse.flow.Flow;
import io.quarkiverse.flow.dsl.FlowWorkflowBuilder;
import io.serverlessworkflow.api.types.Workflow;

@ApplicationScoped
public class TracedFlow extends Flow {

    @Override
    public Workflow descriptor() {
        return FlowWorkflowBuilder.workflow("traced")
                .tasks(
                        function(TracedFlow::greet, Map.class),
                        function(TracedFlow::shout, Map.class),
                        function(TracedFlow::finish, Map.class))
                .build();
    }

    // Deliberately reads the input map (not a fixed set()) so valid and
    // invalid Dev UI input can actually be told apart by their output,
    // rather than every run producing the identical result regardless of
    // what was submitted.
    private static Map<String, Object> greet(Map<String, Object> in) {
        Object name = in.get("name");
        String greeting = (name != null) ? "hello " + name : "hello";
        return Map.of("greeting", greeting);
    }

    private static Map<String, Object> shout(Map<String, Object> in) {
        Map<String, Object> out = new HashMap<>(in);
        out.put("shout", String.valueOf(in.get("greeting")).toUpperCase());
        return out;
    }

    private static Map<String, Object> finish(Map<String, Object> in) {
        Map<String, Object> out = new HashMap<>(in);
        out.put("done", true);
        return out;
    }
}
