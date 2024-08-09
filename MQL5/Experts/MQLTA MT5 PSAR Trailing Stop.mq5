#property link          "https://www.earnforex.com/metatrader-expert-advisors/psar-trailing-stop/"
#property version       "1.06"
#property strict
#property copyright     "EarnForex.com - 2019-2024"
#property description   "This expert advisor will trail the stop-loss following the Parabolic SAR."
#property description   ""
#property description   "WARNING: There is no guarantee that this expert advisor will work as intended. Use at your own risk."
#property description   ""
#property description   "Find more on www.EarnForex.com"
#property icon          "\\Files\\EF-Icon-64x64px.ico"

#include <MQLTA ErrorHandling.mqh>
#include <MQLTA Utils.mqh>
#include <Trade/Trade.mqh>

enum ENUM_CONSIDER
{
    All = -1,                  // ALL ORDERS
    Buy = POSITION_TYPE_BUY,   // BUY ONLY
    Sell = POSITION_TYPE_SELL, // SELL ONLY
};

input string Comment_1 = "====================";  // Expert Advisor Settings
input double PSARStep = 0.02;                     // PSAR Step
input double PSARMax = 0.2;                       // PSAR Max
input int Shift = 0;                              // Shift In The PSAR Value (0=Current Candle)
input string Comment_2 = "====================";  // Orders Filtering Options
input bool OnlyCurrentSymbol = true;              // Apply To Current Symbol Only
input ENUM_CONSIDER OnlyType = All;               // Apply To
input bool UseMagic = false;                      // Filter By Magic Number
input int MagicNumber = 0;                        // Magic Number (if above is true)
input bool UseComment = false;                    // Filter By Comment
input string CommentFilter = "";                  // Comment (if above is true)
input int ProfitPoints = 0;                       // Profit Points to Start Trailing (0 = ignore profit)
input bool EnableTrailingParam = false;           // Enable Trailing Stop
input string Comment_3 = "====================";  // Notification Options
input bool EnableNotify = false;                  // Enable Notifications feature
input bool SendAlert = true;                      // Send Alert Notification
input bool SendApp = true;                        // Send Notification to Mobile
input bool SendEmail = true;                      // Send Notification via Email
input string Comment_3a = "===================="; // Graphical Window
input bool ShowPanel = true;                      // Show Graphical Panel
input string ExpertName = "MQLTA-PSARTS";         // Expert Name (to name the objects)
input int Xoff = 20;                              // Horizontal spacing for the control panel
input int Yoff = 20;                              // Vertical spacing for the control panel
input ENUM_BASE_CORNER ChartCorner = CORNER_LEFT_UPPER; // Chart Corner
input int FontSize = 10;                         // Font Size

int OrderOpRetry = 5;
bool EnableTrailing = EnableTrailingParam;
double DPIScale; // Scaling parameter for the panel based on the screen DPI.
int PanelMovY, PanelLabX, PanelLabY, PanelRecX;

string Symbols[]; // Will store symbols for handles.
int SymbolHandles[]; // Will store actual handles.

CTrade *Trade; // Trading object.

int OnInit()
{
    CleanPanel();
    EnableTrailing = EnableTrailingParam;
    DPIScale = (double)TerminalInfoInteger(TERMINAL_SCREEN_DPI) / 96.0;

    PanelMovY = (int)MathRound(20 * DPIScale);
    PanelLabX = (int)MathRound(150 * DPIScale);
    PanelLabY = PanelMovY;
    PanelRecX = PanelLabX + 4;
    
    if (ShowPanel) DrawPanel();

    ArrayResize(Symbols, 1, 10); // At least one (current symbol) and up to 10 reserved space.
    ArrayResize(SymbolHandles, 1, 10);
    
    Symbols[0] = Symbol();
    SymbolHandles[0] = iSAR(Symbol(), PERIOD_CURRENT, PSARStep, PSARMax);
    
	Trade = new CTrade;

    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
    CleanPanel();
    delete Trade;
}

void OnTick()
{
    if (EnableTrailing) TrailingStop();
    if (ShowPanel) DrawPanel();
}

void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
    if (id == CHARTEVENT_OBJECT_CLICK)
    {
        if (sparam == PanelEnableDisable)
        {
            ChangeTrailingEnabled();
        }
    }
    if (id == CHARTEVENT_KEYDOWN)
    {
        if (lparam == 27)
        {
            if (MessageBox("Are you sure you want to close the EA?", "EXIT?", MB_YESNO) == IDYES)
            {
                ExpertRemove();
            }
        }
    }
}

double GetStopLossBuy(string symbol)
{
    double buf[1];
    int index = FindHandle(symbol);
    if (index == -1) // Handle not found.
    {
        // Create handle.
        int new_size = ArraySize(Symbols) + 1;
        ArrayResize(Symbols, new_size, 10);
        ArrayResize(SymbolHandles, new_size, 10);
        
        index = new_size - 1;
        Symbols[index] = symbol;
        SymbolHandles[index] = iSAR(symbol, PERIOD_CURRENT, PSARStep, PSARMax);
    }
    // Copy buffer.
    int n = CopyBuffer(SymbolHandles[index], 0, Shift, 1, buf);
    if (n < 1)
    {
        Print("PSAR data not ready for " + Symbols[index] + ".");
    }
    return buf[0];
}

double GetStopLossSell(string symbol)
{
    return GetStopLossBuy(symbol);
}

void TrailingStop()
{
    for (int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if (ticket <= 0)
        {
            Print("PositionGetTicket failed " + IntegerToString(GetLastError()) + ".");
            continue;
        }

        if (PositionSelectByTicket(ticket) == false)
        {
            int Error = GetLastError();
            string ErrorText = GetLastErrorText(Error);
            Print("ERROR - Unable to select the position #", IntegerToString(ticket), " - ", Error);
            Print("ERROR - ", ErrorText);
            continue;
        }
        if ((OnlyCurrentSymbol) && (PositionGetString(POSITION_SYMBOL) != Symbol())) continue;
        if ((UseMagic) && (PositionGetInteger(POSITION_MAGIC) != MagicNumber)) continue;
        if ((UseComment) && (StringFind(PositionGetString(POSITION_COMMENT), CommentFilter) < 0)) continue;
        if ((OnlyType != All) && (PositionGetInteger(POSITION_TYPE) != OnlyType)) continue;

        double NewSL = 0;

        string Instrument = PositionGetString(POSITION_SYMBOL);
        double PointSymbol = SymbolInfoDouble(Instrument, SYMBOL_POINT);
        ENUM_POSITION_TYPE PositionType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        if (ProfitPoints > 0) // Check if there is enough profit points on this position.
        {
            if (((PositionType == POSITION_TYPE_BUY)  && ((PositionGetDouble(POSITION_PRICE_CURRENT) - PositionGetDouble(POSITION_PRICE_OPEN)) / PointSymbol < ProfitPoints)) ||
                ((PositionType == POSITION_TYPE_SELL) && ((PositionGetDouble(POSITION_PRICE_OPEN) - PositionGetDouble(POSITION_PRICE_CURRENT)) / PointSymbol < ProfitPoints))) continue;
        }

        double PSAR_SL = 0;
        if (PositionType == POSITION_TYPE_BUY) PSAR_SL = GetStopLossBuy(Instrument);
        else if (PositionType == POSITION_TYPE_SELL) PSAR_SL = GetStopLossSell(Instrument);

        if ((PSAR_SL == 0) || (PSAR_SL == EMPTY_VALUE))
        {
            Print("Not enough historical data - please load more candles for the selected timeframe.");
            return;
        }
        if (PositionType == POSITION_TYPE_BUY)
        {
            if ((Shift > 0) && (PSAR_SL > iLow(Instrument, Period(), Shift))) return; // Shifted PSAR is on the wrong side of price for Buy orders.
        }
        else if (PositionType == POSITION_TYPE_SELL)
        {
            if ((Shift > 0) && (PSAR_SL < iHigh(Instrument, Period(), Shift))) return; // Shifted PSAR is on the wrong side of price for Sell orders.
        }

        int eDigits = (int)SymbolInfoInteger(Instrument, SYMBOL_DIGITS);
        PSAR_SL = NormalizeDouble(PSAR_SL, eDigits);
        double SLPrice = NormalizeDouble(PositionGetDouble(POSITION_SL), eDigits);
        double Spread = SymbolInfoInteger(Instrument, SYMBOL_SPREAD) * PointSymbol;
        double StopLevel = SymbolInfoInteger(Instrument, SYMBOL_TRADE_STOPS_LEVEL) * PointSymbol;
        // Adjust for tick size granularity.
        double TickSize = SymbolInfoDouble(Instrument, SYMBOL_TRADE_TICK_SIZE);
        if (TickSize > 0)
        {
            PSAR_SL = NormalizeDouble(MathRound(PSAR_SL / TickSize) * TickSize, eDigits);
        }
        if ((PositionType == POSITION_TYPE_BUY) && (PSAR_SL < SymbolInfoDouble(Instrument, SYMBOL_BID) - StopLevel))
        {
            if (PSAR_SL > SLPrice)
            {
                ModifyOrder(ticket, PSAR_SL, PositionGetDouble(POSITION_TP));
            }
        }
        else if ((PositionType == POSITION_TYPE_SELL) && (PSAR_SL > SymbolInfoDouble(Instrument, SYMBOL_ASK) + StopLevel))
        {
            if ((PSAR_SL < SLPrice) || (SLPrice == 0))
            {
                ModifyOrder(ticket, PSAR_SL, PositionGetDouble(POSITION_TP));
            }
        }
    }
}

void ModifyOrder(ulong Ticket, double SLPrice, double TPPrice)
{
    string symbol = PositionGetString(POSITION_SYMBOL);
    int eDigits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
    SLPrice = NormalizeDouble(SLPrice, eDigits);
    TPPrice = NormalizeDouble(TPPrice, eDigits);
    for (int i = 1; i <= OrderOpRetry; i++)
    {
        bool res = Trade.PositionModify(Ticket, SLPrice, TPPrice);
        if (!res)
        {
            Print("Wrong position midification request: ", Ticket, " in ", symbol, " at SL = ", SLPrice, ", TP = ", TPPrice);
            return;
        }
		if ((Trade.ResultRetcode() == 10008) || (Trade.ResultRetcode() == 10009) || (Trade.ResultRetcode() == 10010)) // Success.
        {
            Print("TRADE - UPDATE SUCCESS - Position ", Ticket, " in ", symbol, ": new stop-loss ", SLPrice, " new take-profit ", TPPrice);
            NotifyStopLossUpdate(Ticket, SLPrice, symbol);
            break;
        }
        else
        {
			Print("Position Modify Return Code: ", Trade.ResultRetcodeDescription());
            int Error = GetLastError();
            string ErrorText = GetLastErrorText(Error);
            Print("ERROR - UPDATE FAILED - error modifying position ", Ticket, " in ", symbol, " return error: ", Error, " Open=", PositionGetDouble(POSITION_PRICE_OPEN),
                  " Old SL=", PositionGetDouble(POSITION_SL), " Old TP=", PositionGetDouble(POSITION_TP),
                  " New SL=", SLPrice, " New TP=", TPPrice, " Bid=", SymbolInfoDouble(symbol, SYMBOL_BID), " Ask=", SymbolInfoDouble(symbol, SYMBOL_ASK));
            Print("ERROR - ", ErrorText);
        }
    }
}

void NotifyStopLossUpdate(ulong OrderNumber, double SLPrice, string symbol)
{
    if (!EnableNotify) return;
    if ((!SendAlert) && (!SendApp) && (!SendEmail)) return;
    string EmailSubject = ExpertName + " " + symbol + " Notification ";
    string EmailBody = AccountCompany() + " - " + AccountName() + " - " + IntegerToString(AccountNumber()) + "\r\n" + ExpertName + " Notification for " + symbol + "\r\n";
    EmailBody += "Stop-loss for position " + IntegerToString(OrderNumber) + " moved to " + DoubleToString(SLPrice, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));
    string AlertText = symbol + " - stop-loss for position " + IntegerToString(OrderNumber) + " was moved to " + DoubleToString(SLPrice, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));
    string AppText = AccountCompany() + " - " + AccountName() + " - " + IntegerToString(AccountNumber()) + " - " + ExpertName + " - " + symbol + " - ";
    AppText += "stop-loss for position: " + IntegerToString(OrderNumber) + " was moved to " + DoubleToString(SLPrice, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)) + "";
    if (SendAlert) Alert(AlertText);
    if (SendEmail)
    {
        if (!SendMail(EmailSubject, EmailBody)) Print("Error sending email " + IntegerToString(GetLastError()));
    }
    if (SendApp)
    {
        if (!SendNotification(AppText)) Print("Error sending notification " + IntegerToString(GetLastError()));
    }
}

string PanelBase = ExpertName + "-P-BAS";
string PanelLabel = ExpertName + "-P-LAB";
string PanelEnableDisable = ExpertName + "-P-ENADIS";
void DrawPanel()
{
    int SignX = 1;
    int YAdjustment = 0;
    if ((ChartCorner == CORNER_RIGHT_UPPER) || (ChartCorner == CORNER_RIGHT_LOWER))
    {
        SignX = -1; // Correction for right-side panel position.
    }
    if ((ChartCorner == CORNER_RIGHT_LOWER) || (ChartCorner == CORNER_LEFT_LOWER))
    {
        YAdjustment = (PanelMovY + 2) * 2 + 1 - PanelLabY; // Correction for upper side panel position.
    }
    string PanelText = "MQLTA PSARTS";
    string PanelToolTip = "PSAR Trailing Stop-Loss by EarnForex.com";
    int Rows = 1;
    ObjectCreate(0, PanelBase, OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSetInteger(0, PanelBase, OBJPROP_CORNER, ChartCorner);
    ObjectSetInteger(0, PanelBase, OBJPROP_XDISTANCE, Xoff);
    ObjectSetInteger(0, PanelBase, OBJPROP_YDISTANCE, Yoff + YAdjustment);
    ObjectSetInteger(0, PanelBase, OBJPROP_XSIZE, PanelRecX);
    ObjectSetInteger(0, PanelBase, OBJPROP_YSIZE, (PanelMovY + 2) * 2 + 2);
    ObjectSetInteger(0, PanelBase, OBJPROP_BGCOLOR, clrWhite);
    ObjectSetInteger(0, PanelBase, OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(0, PanelBase, OBJPROP_HIDDEN, true);
    ObjectSetInteger(0, PanelBase, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, PanelBase, OBJPROP_COLOR, clrBlack);

    DrawEdit(PanelLabel,
             Xoff + 2 * SignX,
             Yoff + 2,
             PanelLabX,
             PanelLabY,
             true,
             FontSize,
             PanelToolTip,
             ALIGN_CENTER,
             "Consolas",
             PanelText,
             false,
             clrNavy,
             clrKhaki,
             clrBlack);
    ObjectSetInteger(0, PanelLabel, OBJPROP_CORNER, ChartCorner);

    string EnableDisabledText = "";
    color EnableDisabledColor = clrNavy;
    color EnableDisabledBack = clrKhaki;
    if (EnableTrailing)
    {
        EnableDisabledText = "TRAILING ENABLED";
        EnableDisabledColor = clrWhite;
        EnableDisabledBack = clrDarkGreen;
    }
    else
    {
        EnableDisabledText = "TRAILING DISABLED";
        EnableDisabledColor = clrWhite;
        EnableDisabledBack = clrDarkRed;
    }

    DrawEdit(PanelEnableDisable,
             Xoff + 2 * SignX,
             Yoff + (PanelMovY + 1) * Rows + 2,
             PanelLabX,
             PanelLabY,
             true,
             FontSize,
             "Click to Enable or Disable the Trailing Stop Feature",
             ALIGN_CENTER,
             "Consolas",
             EnableDisabledText,
             false,
             EnableDisabledColor,
             EnableDisabledBack,
             clrBlack);
    ObjectSetInteger(0, PanelEnableDisable, OBJPROP_CORNER, ChartCorner);
    ChartRedraw();
}

void CleanPanel()
{
    ObjectsDeleteAll(0, ExpertName + "-P-");
}

void ChangeTrailingEnabled()
{
    if (EnableTrailing == false)
    {
        if ((!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) && (!MQLInfoInteger(MQL_TRADE_ALLOWED)))
        {
            MessageBox("Please enable Live Trading in the EA's options and Automated Trading in the platform's options.", "WARNING", MB_OK);
        }
        else if (!MQLInfoInteger(MQL_TRADE_ALLOWED))
        {
            MessageBox("Please enable Live Trading in the EA's options.", "WARNING", MB_OK);
        }
        else if (!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
        {
            MessageBox("Please enable Automated Trading in the platform's options.", "WARNING", MB_OK);
        }
        else EnableTrailing = true;
    }
    else EnableTrailing = false;
    DrawPanel();
}

// Tries to find a handle for a symbol in arrays.
// Returns the index if found, -1 otherwise.
int FindHandle(string symbol)
{
    int size = ArraySize(Symbols);
    for (int i = 0; i < size; i++)
    {
        if (Symbols[i] == symbol) return i;
    }
    return -1;
}
//+------------------------------------------------------------------+