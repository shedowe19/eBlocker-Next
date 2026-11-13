/*
 * Copyright 2020 eBlocker Open Source UG (haftungsbeschraenkt)
 *
 * Licensed under the EUPL, Version 1.2 or - as soon they will be
 * approved by the European Commission - subsequent versions of the EUPL
 * (the "License"); You may not use this work except in compliance with
 * the License. You may obtain a copy of the License at:
 *
 *   https://joinup.ec.europa.eu/page/eupl-text-11-12
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" basis,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
 * implied. See the License for the specific language governing
 * permissions and limitations under the License.
 */
package org.eblocker.server.common.registration;

import org.eblocker.registration.DeviceRegistrationResponse;
import org.eblocker.registration.ProductInfo;
import org.eblocker.registration.error.ClientRequestException;
import org.eblocker.server.common.exceptions.NetworkConnectionException;
import org.junit.jupiter.api.Test;
import org.mockito.InOrder;

import javax.net.ssl.SSLContext;
import javax.ws.rs.ProcessingException;
import javax.ws.rs.client.Client;
import javax.ws.rs.client.Entity;
import javax.ws.rs.client.Invocation;
import javax.ws.rs.client.WebTarget;
import javax.ws.rs.core.MediaType;
import javax.ws.rs.core.Response;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/** Transport lifecycle coverage only: no live backend or license activation. */
class DeviceRegistrationClientLifecycleTest extends DeviceRegistrationTestBase {
    @Test
    void closesResponseThenClientOnSuccess() throws Exception {
        for (boolean post : new boolean[]{false, true}) {
            Fixture f = new Fixture(post);
            when(f.response.getStatus()).thenReturn(post ? 201 : 200);
            Object expected = post ? mock(DeviceRegistrationResponse.class) : mock(ProductInfo.class);
            doReturn(expected).when(f.response).readEntity(any(Class.class));
            assertSame(expected, f.invoke());
            f.verifyClosed();
        }
    }

    @Test
    void closesResponseThenClientOnHttpError() throws Exception {
        for (boolean post : new boolean[]{false, true}) {
            Fixture f = new Fixture(post);
            when(f.response.getStatus()).thenReturn(400);
            ClientRequestException error = assertThrows(ClientRequestException.class, f::invoke);
            assertEquals(400, error.getStatus());
            f.verifyClosed();
        }
    }

    @Test
    void closesResourcesWhenDecodingFails() throws Exception {
        for (boolean post : new boolean[]{false, true}) {
            Fixture f = new Fixture(post);
            when(f.response.getStatus()).thenReturn(200);
            when(f.response.readEntity(any(Class.class))).thenThrow(new ProcessingException("invalid JSON"));
            if (post) {
                assertThrows(NetworkConnectionException.class, f::invoke);
            } else {
                assertThrows(ProcessingException.class, f::invoke);
            }
            f.verifyClosed();
        }
    }

    @Test
    void closesClientWhenTransportFailsBeforeResponse() throws Exception {
        for (boolean post : new boolean[]{false, true}) {
            Fixture f = new Fixture(post);
            if (post) {
                when(f.request.post(any(Entity.class))).thenThrow(new ProcessingException("unreachable"));
            } else {
                when(f.request.get()).thenThrow(new ProcessingException("unreachable"));
            }
            if (post) {
                assertThrows(NetworkConnectionException.class, f::invoke);
            } else {
                assertThrows(ProcessingException.class, f::invoke);
            }
            verify(f.client).close();
            verifyNoInteractions(f.response);
        }
    }

    @Test
    void closesClientEvenWhenResponseCleanupFails() throws Exception {
        for (boolean post : new boolean[]{false, true}) {
            Fixture f = new Fixture(post);
            when(f.response.getStatus()).thenReturn(200);
            doThrow(new IllegalStateException("cleanup failed")).when(f.response).close();
            assertThrows(IllegalStateException.class, f::invoke);
            f.verifyClosed();
        }
    }

    private class Fixture {
        final boolean post;
        final Client client = mock(Client.class);
        final WebTarget target = mock(WebTarget.class);
        final Invocation.Builder request = mock(Invocation.Builder.class, RETURNS_SELF);
        final Response response = mock(Response.class);
        final DeviceRegistrationClient subject;

        Fixture(boolean post) throws Exception {
            this.post = post;
            subject = spy(createDeviceRegistrationClient());
            doReturn(client).when(subject).createClient(any(SSLContext.class));
            when(client.target(anyString())).thenReturn(target);
            when(target.request(MediaType.APPLICATION_JSON_TYPE)).thenReturn(request);
            when(request.get()).thenReturn(response);
            when(request.post(any(Entity.class))).thenReturn(response);
        }

        Object invoke() {
            return post ? subject.register(null) : subject.getProductInfo();
        }

        void verifyClosed() {
            InOrder order = inOrder(response, client);
            order.verify(response).close();
            order.verify(client).close();
        }
    }
}
