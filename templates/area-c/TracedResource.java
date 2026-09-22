package @@PACKAGE@@;

import java.util.Map;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;

import io.smallrye.mutiny.Uni;

@Path("/traced-flow")
@ApplicationScoped
@Produces(MediaType.APPLICATION_JSON)
public class TracedResource {

    @Inject
    TracedFlow traced;

    @GET
    public Uni<TracedResult> traced() {
        return traced
                .startInstance(Map.of())
                .onItem()
                .transform(w -> w.as(TracedResult.class).orElseThrow());
    }

    @GET
    @Path("/debug")
    public Uni<Object> debug() {
        return traced
                .startInstance(Map.of())
                .onItem()
                .transform(w -> w.asMap().orElseThrow());
    }
}
