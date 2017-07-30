package exfix;

import java.util.Scanner;

public class Main {

    /**
     * @param args
     */
    public static void main(String[] args) throws Exception {
        FixAcceptor acceptor = new FixAcceptor();
        acceptor.setApplication(new FixApplication());
        acceptor.start();
        System.out.println("Press ENTER to stop...");
        Scanner scanner = new Scanner(System.in);
        scanner.nextLine();
        acceptor.stop();
    }

}
