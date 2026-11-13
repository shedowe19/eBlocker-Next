package org.eblocker.server.common.network;

import org.eblocker.server.common.data.DataSource;
import org.eblocker.server.common.network.unix.EblockerDnsServer;
import org.junit.Test;
import org.mockito.ArgumentCaptor;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import static org.mockito.Mockito.*;

public class TorControlAuthenticationTest {
    private void attempt(String password, TelnetConnection connection) {
        DataSource data = mock(DataSource.class);
        ScheduledExecutorService executor = mock(ScheduledExecutorService.class);
        TorController controller = new TorController(9051, data, mock(EblockerDnsServer.class), connection,
                new TorExitNodeCountries(data), mock(TorConfiguration.class), () -> password);
        controller.startCheckingConnection(executor, 100);
        ArgumentCaptor<Runnable> task = ArgumentCaptor.forClass(Runnable.class);
        verify(executor).scheduleWithFixedDelay(task.capture(), eq(0L), eq(100L), eq(TimeUnit.MILLISECONDS));
        task.getValue().run();
    }

    @Test public void absentAndInvalidSecretsNeverOpenConnection() {
        for (String password : new String[]{null, "", "  ", "bad\ncommand", "bad\rcommand", "bad\u0000", "\u00e4", "x".repeat(1025)}) {
            TelnetConnection connection = mock(TelnetConnection.class);
            attempt(password, connection);
            verifyNoInteractions(connection);
        }
    }

    @Test public void rejectedAuthenticationClosesConnection() throws Exception {
        TelnetConnection connection = mock(TelnetConnection.class);
        when(connection.readLine()).thenReturn("515 Authentication failed");
        attempt("unit-test", connection);
        verify(connection).writeLine("authenticate 756e69742d74657374");
        verify(connection).close();
    }
}
