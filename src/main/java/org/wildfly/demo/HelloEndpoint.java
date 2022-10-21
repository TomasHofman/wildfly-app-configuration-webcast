package org.wildfly.demo;

import javax.ws.rs.GET;
import javax.ws.rs.Path;
import javax.ws.rs.Produces;
import javax.ws.rs.core.MediaType;

@Path("/")
@Produces(MediaType.TEXT_PLAIN)
public class HelloEndpoint {

    @GET
    @Path("hello")
    public String getHelloWorld() {
        return "Hello there!\n";
    }

}
