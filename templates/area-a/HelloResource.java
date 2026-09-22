package @@PACKAGE@@;

import java.util.Map;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;

import io.smallrye.mutiny.Uni;

@Path("/hello-flow")
@ApplicationScoped
@Produces(MediaType.APPLICATION_JSON)
public class HelloResource {

    @Inject
    HelloFlow hello;

    @GET
    public Uni<Message> hello() {
        return hello
                .startInstance(Map.of())
                .onItem()
                .transform(w -> w.as(Message.class).orElseThrow());
    }

    @GET
    @Path("/debug")
    public Uni<Object> debug() {
        return hello
                .startInstance(Map.of())
                .onItem()
                .transform(w -> w.asMap().orElseThrow());
    }
}
