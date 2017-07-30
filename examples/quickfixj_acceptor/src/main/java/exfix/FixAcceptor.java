package exfix;

import quickfix.*;
import quickfix.mina.acceptor.DynamicAcceptorSessionProvider;

import java.io.InputStream;
import java.net.InetSocketAddress;

/**
 *
 */
public class FixAcceptor {

    private static final String SESSION_SETTINGS_LOCATION = "exfix/acceptor.cfg";

    private Application application;
    private SocketAcceptor socketAcceptor;

    public void start() throws FieldConvertError, ConfigError {
        MemoryStoreFactory messageStoreFactory = new MemoryStoreFactory();
        InputStream settingsInputStream = ClassLoader.getSystemResourceAsStream(SESSION_SETTINGS_LOCATION);
        SessionSettings sessionSettings = new SessionSettings(settingsInputStream);
        LogFactory logFactory = new SLF4JLogFactory(sessionSettings);
        DefaultMessageFactory messageFactory = new DefaultMessageFactory();
        socketAcceptor = new SocketAcceptor(application, messageStoreFactory, sessionSettings,
                logFactory, messageFactory);

        int port = sessionSettings.getInt("SocketAcceptPort");
        InetSocketAddress socketAddress = new InetSocketAddress("0.0.0.0", port);
        SessionID templateSessionID = new SessionID(
                sessionSettings.getString("BeginString"), "*", "*");

        socketAcceptor.setSessionProvider(socketAddress, new DynamicAcceptorSessionProvider(sessionSettings,
                templateSessionID, application, messageStoreFactory, logFactory, messageFactory));

        socketAcceptor.start();
    }

    public void stop() {
        if (socketAcceptor != null) {
            socketAcceptor.stop();
            socketAcceptor = null;
        }
    }

    public void setApplication(Application application) {
        this.application = application;
    }
}
