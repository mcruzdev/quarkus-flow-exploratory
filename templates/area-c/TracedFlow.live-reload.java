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

    private static Map<String, Object> greet(Map<String, Object> in) {
        Object name = in.get("name");
        String greeting = (name != null) ? "hello from live reload " + name : "hello from live reload";
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
