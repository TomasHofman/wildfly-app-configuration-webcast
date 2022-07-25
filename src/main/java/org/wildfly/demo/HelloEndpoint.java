package org.wildfly.demo;

import javax.ws.rs.GET;
import javax.ws.rs.Path;
import javax.ws.rs.Produces;
import javax.ws.rs.core.MediaType;

import org.jboss.logging.Logger;

@Path("/")
@Produces(MediaType.APPLICATION_JSON)
public class HelloEndpoint {

    private final Logger logger = Logger.getLogger(getClass());

    @GET
    @Path("hello")
    public String getHelloWorldJSON() {
        logger.debugf("Received a /hello endpoint request");
        return "{\"result\":\"Hello there!\"}";
    }

}
