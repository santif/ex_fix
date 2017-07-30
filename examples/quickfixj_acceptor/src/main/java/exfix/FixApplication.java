package exfix;

import quickfix.*;
import quickfix.field.*;
import quickfix.fix50sp2.ExecutionReport;
import quickfix.fix50sp2.NewOrderSingle;

/**
 *
 */
public class FixApplication extends ApplicationAdapter {

    private long orderId = 0;

    @Override
    public void fromApp(Message message, SessionID sessionId) throws FieldNotFound, IncorrectDataFormat,
            IncorrectTagValue, UnsupportedMessageType {
        String msgType = message.getHeader().getString(MsgType.FIELD);
        switch (msgType) {
            case NewOrderSingle.MSGTYPE:
                fillNewOrderSingle(message, sessionId);
                break;
        }
    }

    /**
     * @param message
     * @param sessionId
     */
    public void fillNewOrderSingle(Message message, SessionID sessionId) throws FieldNotFound {
        String orderAccount = message.getString(Account.FIELD);
        String orderSymbol = message.getString(Symbol.FIELD);
        Double orderQuantity = message.getDouble(OrderQty.FIELD);
        Double orderPrice = message.getDouble(Price.FIELD);
        Character orderSide = message.getChar(Side.FIELD);

        String id = String.valueOf(orderId++);
        OrderID orderID = new OrderID(id);
        ExecID execID = new ExecID(id);
        ExecType execType = new ExecType(ExecType.FILL);
        OrdStatus ordStatus = new OrdStatus(OrdStatus.FILLED);
        Side side = new Side(orderSide);
        LeavesQty leavesQty = new LeavesQty(0.0);
        CumQty cumQty = new CumQty(orderQuantity);

        ExecutionReport er = new ExecutionReport(orderID, execID, execType, ordStatus, side, leavesQty, cumQty);
        er.set(new Account(orderAccount));
        er.set(new Symbol(orderSymbol));
        er.set(new LastPx(orderPrice));
        er.set(new AvgPx(orderPrice));

        try {
            Session.sendToTarget(er, sessionId);
        } catch (SessionNotFound sessionNotFound) {
            sessionNotFound.printStackTrace();
        }
    }

}
