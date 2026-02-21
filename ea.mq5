//+------------------------------------------------------------------+
//|  SpeedPanel.mq5  (1.97 - BID/ASK/SPREAD SEPARATED)               |
//+------------------------------------------------------------------+
#property strict
#property version     "1.97"
#property description "Scalp panel with Bid / Ask / Spread / AVG / P/L / Pips"

#include <Trade\Trade.mqh>
CTrade trade;

//=== Inputs ========================================================
input int    PanelRightX  = 40;
input int    PanelBottomY = 40;
input ulong  MagicNumber  = 123456;
input string EntrySound   = "alert.wav";
input string ExitSound    = "alert2.wav";

//=== ロット初期値 ==================================================
double DefaultLots1 = 4;
double DefaultLots2 = 2;
double DefaultLots3 = 0.8;
double DefaultLots4 = 0.4;

// CLOSE ALL ボタン
string CloseBtnText   = "CLOSE ALL";
color  CloseBtnColor  = clrBlack;
int    CloseBtnWidth  = 240;
int    CloseBtnHeight = 64;

// UIサイズ
int rowHeight   = 80;
int editWidth   = 100;
int buttonWidth = 100;
int buttonHeight = 64;

int panelPaddingLeft   = 32;
int panelPaddingRight  = 32;
int panelPaddingTop    = 32;
int panelPaddingBottom = 32;

// 上部情報ブロック
int infoLineHeight     = 32;
int infoLineGap        = 16;
int infoBlockGapToRows = 32;

int rowsOffsetFromTop = 0;

int marginEditToSell = 8;
int marginSellToBuy  = 8;

int gapRowsToClose = 16;

string prefix       = "UCP_";
const int ROW_COUNT = 4;

color clrBorder  = (color)0xDDDDDD;
color clrBgPanel = clrWhite;
color clrText    = clrBlack;

color clrSellBg  = clrDodgerBlue;
color clrBuyBg   = clrRed;
color clrBtnText = clrWhite;

// パネルサイズ＆位置
int panelWidth  = 0;
int panelHeight = 0;
int panelLeft   = 0;
int panelTop    = 0;

// ラベル列の幅
int LabelColumnWidth = 120;

//=== AVG キャッシュ ================================================
double cachedAvgPrice = 0.0;
bool   avgDirty       = true;

//===================================================================
// Forward Declarations
void UpdateLayout();
void UpdatePositionStats();
void CreateLabel(string name,int x,int y,string text);
void CreateButton(string name,int x,int y,int w,int h,string text,
                  color bgColor,color textColor);
void CreateEdit(string name,int x,int y,int w,int h,
                color bgColor,color textColor);
void CreatePanelBackground(string name,int x,int y,int w,int h,
                           color bgColor,color borderColor);
//===================================================================


//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber((int)MagicNumber);
   ObjectsDeleteAll(0, prefix);

   int infoBlockHeight =
      infoLineHeight * 6 +   // Bid / Ask / Spread / AVG / P/L / Pips
      infoLineGap    * 5;

   rowsOffsetFromTop = infoBlockHeight + infoBlockGapToRows;

   panelWidth =
      panelPaddingLeft  +
      editWidth         +
      marginEditToSell  +
      buttonWidth       +
      marginSellToBuy   +
      buttonWidth       +
      panelPaddingRight;

   panelHeight =
      panelPaddingTop           +
      rowsOffsetFromTop         +
      (ROW_COUNT - 1) * rowHeight +
      buttonHeight              +
      gapRowsToClose            +
      CloseBtnHeight            +
      panelPaddingBottom;

   CreatePanelBackground(prefix + "BG_PANEL", 0, 0, panelWidth, panelHeight,
                         clrBgPanel, clrBorder);

   // === ラベル左列 ===
   CreateLabel(prefix + "HDR_BID_L",        0, 0, "Bid");
   CreateLabel(prefix + "HDR_ASK_L",        0, 0, "Ask");
   CreateLabel(prefix + "HDR_SPREAD_L",     0, 0, "Spread");
   CreateLabel(prefix + "HDR_STATS_AVG_L",  0, 0, "AVG");
   CreateLabel(prefix + "HDR_STATS_PL_L",   0, 0, "P/L");
   CreateLabel(prefix + "HDR_STATS_PIPS_L", 0, 0, "Pips");

   // === ラベル右列 ===
   CreateLabel(prefix + "HDR_BID",        0, 0, ": -");
   CreateLabel(prefix + "HDR_ASK",        0, 0, ": -");
   CreateLabel(prefix + "HDR_SPREAD",     0, 0, ": -");
   CreateLabel(prefix + "HDR_STATS_AVG",  0, 0, ": -");
   CreateLabel(prefix + "HDR_STATS_PL",   0, 0, ": -");
   CreateLabel(prefix + "HDR_STATS_PIPS", 0, 0, ": -");

   // === ボタン列 ===
   for(int i = 0; i < ROW_COUNT; i++)
   {
      string idx      = IntegerToString(i + 1);
      string editName = prefix + "EDIT_VOL_" + idx;

      CreateEdit(editName, 0, 0, editWidth, buttonHeight, clrWhite, clrText);

      double initLots =
         (i == 0 ? DefaultLots1 :
          i == 1 ? DefaultLots2 :
          i == 2 ? DefaultLots3 : DefaultLots4);

      ObjectSetString(0, editName, OBJPROP_TEXT, DoubleToString(initLots, 1));

      CreateButton(prefix + "BTN_SELL_" + idx, 0, 0,
                   buttonWidth, buttonHeight, "SELL", clrSellBg, clrBtnText);

      CreateButton(prefix + "BTN_BUY_" + idx, 0, 0,
                   buttonWidth, buttonHeight, "BUY",  clrBuyBg,  clrBtnText);
   }

   CreateButton(prefix + "BTN_CLOSE", 0, 0,
                CloseBtnWidth, CloseBtnHeight,
                CloseBtnText, CloseBtnColor, clrBtnText);

   UpdateLayout();
   UpdatePositionStats();
   ChartRedraw();
   return(INIT_SUCCEEDED);
}


//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, prefix);
}


//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
{
   MqlTick tick;
   if(SymbolInfoTick(_Symbol, tick))
   {
      double bid = tick.bid;
      double ask = tick.ask;

      ObjectSetString(0, prefix + "HDR_BID",
                      OBJPROP_TEXT, ": " + DoubleToString(bid, _Digits));

      ObjectSetString(0, prefix + "HDR_ASK",
                      OBJPROP_TEXT, ": " + DoubleToString(ask, _Digits));

      double pipFactor  = (_Digits == 3 || _Digits == 5) ? 10.0 : 1.0;
      double spreadPips = (ask - bid) / _Point / pipFactor;

      string spreadStr =
         DoubleToString(spreadPips, (MathAbs(spreadPips) < 0.1 ? 3 : 1));

      ObjectSetString(0, prefix + "HDR_SPREAD",
                      OBJPROP_TEXT, ": " + spreadStr);
   }

   UpdatePositionStats();
}


//+------------------------------------------------------------------+
//| OnChartEvent                                                     |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,const long &l,const double &d,const string &s)
{
   if(id == CHARTEVENT_CHART_CHANGE)
   {
      UpdateLayout();
      ChartRedraw();
      return;
   }

   if(id != CHARTEVENT_OBJECT_CLICK)
      return;

   string name = s;

   if(name == prefix + "BTN_CLOSE")
   {
      CloseAllPositionsOfSymbol(_Symbol);
      UpdatePositionStats();
      return;
   }

   if(StringFind(name, prefix + "BTN_SELL_") == 0)
   {
      int idx = (int)StringToInteger(
         StringSubstr(name, StringLen(prefix + "BTN_SELL_")));
      OpenPosition(false, idx);
      return;
   }

   if(StringFind(name, prefix + "BTN_BUY_") == 0)
   {
      int idx = (int)StringToInteger(
         StringSubstr(name, StringLen(prefix + "BTN_BUY_")));
      OpenPosition(true, idx);
      return;
   }
}


//+------------------------------------------------------------------+
//| UpdateLayout                                                     |
//+------------------------------------------------------------------+
void UpdateLayout()
{
   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
   int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);

   panelLeft = cw - PanelRightX  - panelWidth;
   panelTop  = ch - PanelBottomY - panelHeight;

   ObjectSetInteger(0, prefix + "BG_PANEL", OBJPROP_XDISTANCE, panelLeft);
   ObjectSetInteger(0, prefix + "BG_PANEL", OBJPROP_YDISTANCE, panelTop);

   int xLabel = panelLeft + panelPaddingLeft;
   int xValue = xLabel   + LabelColumnWidth;

   int y0 = panelTop + panelPaddingTop;

   int yBid    = y0;
   int yAsk    = yBid    + infoLineHeight + infoLineGap;
   int ySpread = yAsk    + infoLineHeight + infoLineGap;
   int yAvg    = ySpread + infoLineHeight + infoLineGap;
   int yPL     = yAvg    + infoLineHeight + infoLineGap;
   int yPips   = yPL     + infoLineHeight + infoLineGap;

   ObjectSetInteger(0, prefix + "HDR_BID_L", OBJPROP_XDISTANCE, xLabel);
   ObjectSetInteger(0, prefix + "HDR_BID_L", OBJPROP_YDISTANCE, yBid);
   ObjectSetInteger(0, prefix + "HDR_BID",   OBJPROP_XDISTANCE, xValue);
   ObjectSetInteger(0, prefix + "HDR_BID",   OBJPROP_YDISTANCE, yBid);

   ObjectSetInteger(0, prefix + "HDR_ASK_L", OBJPROP_XDISTANCE, xLabel);
   ObjectSetInteger(0, prefix + "HDR_ASK_L", OBJPROP_YDISTANCE, yAsk);
   ObjectSetInteger(0, prefix + "HDR_ASK",   OBJPROP_XDISTANCE, xValue);
   ObjectSetInteger(0, prefix + "HDR_ASK",   OBJPROP_YDISTANCE, yAsk);

   ObjectSetInteger(0, prefix + "HDR_SPREAD_L", OBJPROP_XDISTANCE, xLabel);
   ObjectSetInteger(0, prefix + "HDR_SPREAD_L", OBJPROP_YDISTANCE, ySpread);
   ObjectSetInteger(0, prefix + "HDR_SPREAD",   OBJPROP_XDISTANCE, xValue);
   ObjectSetInteger(0, prefix + "HDR_SPREAD",   OBJPROP_YDISTANCE, ySpread);

   ObjectSetInteger(0, prefix + "HDR_STATS_AVG_L", OBJPROP_XDISTANCE, xLabel);
   ObjectSetInteger(0, prefix + "HDR_STATS_AVG_L", OBJPROP_YDISTANCE, yAvg);
   ObjectSetInteger(0, prefix + "HDR_STATS_AVG",   OBJPROP_XDISTANCE, xValue);
   ObjectSetInteger(0, prefix + "HDR_STATS_AVG",   OBJPROP_YDISTANCE, yAvg);

   ObjectSetInteger(0, prefix + "HDR_STATS_PL_L", OBJPROP_XDISTANCE, xLabel);
   ObjectSetInteger(0, prefix + "HDR_STATS_PL_L", OBJPROP_YDISTANCE, yPL);
   ObjectSetInteger(0, prefix + "HDR_STATS_PL",   OBJPROP_XDISTANCE, xValue);
   ObjectSetInteger(0, prefix + "HDR_STATS_PL",   OBJPROP_YDISTANCE, yPL);

   ObjectSetInteger(0, prefix + "HDR_STATS_PIPS_L", OBJPROP_XDISTANCE, xLabel);
   ObjectSetInteger(0, prefix + "HDR_STATS_PIPS_L", OBJPROP_YDISTANCE, yPips);
   ObjectSetInteger(0, prefix + "HDR_STATS_PIPS",   OBJPROP_XDISTANCE, xValue);
   ObjectSetInteger(0, prefix + "HDR_STATS_PIPS",   OBJPROP_YDISTANCE, yPips);

   for(int i = 0; i < ROW_COUNT; i++)
   {
      string idx      = IntegerToString(i + 1);
      string editName = prefix + "EDIT_VOL_" + idx;
      string sellBtn  = prefix + "BTN_SELL_" + idx;
      string buyBtn   = prefix + "BTN_BUY_"  + idx;

      int rowY  = panelTop + panelPaddingTop + rowsOffsetFromTop + i * rowHeight;
      int editX = panelLeft + panelPaddingLeft;

      ObjectSetInteger(0, editName, OBJPROP_XDISTANCE, editX);
      ObjectSetInteger(0, editName, OBJPROP_YDISTANCE, rowY);
      ObjectSetInteger(0, editName, OBJPROP_XSIZE,     editWidth);
      ObjectSetInteger(0, editName, OBJPROP_YSIZE,     buttonHeight);

      int sellX = editX + editWidth + marginEditToSell;

      ObjectSetInteger(0, sellBtn, OBJPROP_XDISTANCE, sellX);
      ObjectSetInteger(0, sellBtn, OBJPROP_YDISTANCE, rowY);

      ObjectSetInteger(0, buyBtn, OBJPROP_XDISTANCE,
                       sellX + buttonWidth + marginSellToBuy);
      ObjectSetInteger(0, buyBtn, OBJPROP_YDISTANCE, rowY);
   }

   int lastRowTop =
      panelTop + panelPaddingTop + rowsOffsetFromTop +
      (ROW_COUNT - 1) * rowHeight;

   int closeY = lastRowTop + buttonHeight + gapRowsToClose;
   int closeX = panelLeft + (panelWidth - CloseBtnWidth) / 2;

   ObjectSetInteger(0, prefix + "BTN_CLOSE", OBJPROP_XDISTANCE, closeX);
   ObjectSetInteger(0, prefix + "BTN_CLOSE", OBJPROP_YDISTANCE, closeY);
}


//+------------------------------------------------------------------+
//| 平均レート・P/L・Pips                                            |
//+------------------------------------------------------------------+
void UpdatePositionStats()
{
   double totalVol   = 0.0;
   double totalCost  = 0.0;
   double totalProfit= 0.0;
   double netLotsDir = 0.0;
   bool   hasPips    = false;
   double pips       = 0.0;

   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      double vol   = PositionGetDouble(POSITION_VOLUME);
      double price = PositionGetDouble(POSITION_PRICE_OPEN);
      double pl    = PositionGetDouble(POSITION_PROFIT);
      long   type  = PositionGetInteger(POSITION_TYPE);

      totalVol    += vol;
      if(avgDirty) totalCost += vol * price;
      totalProfit += pl;
      netLotsDir  += (type == POSITION_TYPE_BUY ? vol : -vol);
   }

   string avgText  = ": -";
   string plText   = ": -";
   string pipsText = ": -";

   color avgColor  = clrText;
   color plColor   = clrText;
   color pipsColor = clrText;

   if(totalVol > 0.0)
   {
      double avgPrice = totalCost / totalVol;
      cachedAvgPrice = avgPrice;

      avgText = ": " + DoubleToString(avgPrice, _Digits);
      plText  = ": " + IntegerToString((int)MathRound(totalProfit));

      MqlTick tick;
      if(SymbolInfoTick(_Symbol, tick))
      {
         double cur =
            (netLotsDir > 0.0 ? tick.bid :
             netLotsDir < 0.0 ? tick.ask :
             (tick.bid + tick.ask) / 2.0);

         double pipFactor = (_Digits == 3 || _Digits == 5 ? 10.0 : 1.0);
         double diff      = (cur - cachedAvgPrice);
         double sign      = (netLotsDir >= 0.0 ? 1.0 : -1.0);

         pips    = diff / _Point / pipFactor * sign;
         pipsText= ": " + DoubleToString(pips, 1);
         hasPips = true;
      }

      if(totalProfit < 0.0) plColor = clrRed;
      if(hasPips && pips < 0.0) pipsColor = clrRed;
   }

   ObjectSetString(0, prefix + "HDR_STATS_AVG",  OBJPROP_TEXT, avgText);
   ObjectSetString(0, prefix + "HDR_STATS_PL",   OBJPROP_TEXT, plText);
   ObjectSetString(0, prefix + "HDR_STATS_PIPS", OBJPROP_TEXT, pipsText);

   ObjectSetInteger(0, prefix + "HDR_STATS_AVG",  OBJPROP_COLOR, avgColor);
   ObjectSetInteger(0, prefix + "HDR_STATS_PL",   OBJPROP_COLOR, plColor);
   ObjectSetInteger(0, prefix + "HDR_STATS_PIPS", OBJPROP_COLOR, pipsColor);
}


//+------------------------------------------------------------------+
//| OpenPosition                                                     |
//+------------------------------------------------------------------+
void OpenPosition(bool isBuy,int index)
{
   string editName = prefix + "EDIT_VOL_" + IntegerToString(index);
   string txt      = ObjectGetString(0, editName, OBJPROP_TEXT);

   StringTrimLeft(txt);
   StringTrimRight(txt);

   double volume = StringToDouble(txt);

   double minV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(volume <= 0.0) return;

   volume = MathFloor(volume / step) * step;
   volume = MathMax(volume, minV);
   volume = MathMin(volume, maxV);

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;

   trade.SetExpertMagicNumber((int)MagicNumber);

   bool ok =
      (isBuy ?
         trade.Buy(volume, _Symbol, tick.ask, 0, 0, "UCP Buy") :
         trade.Sell(volume, _Symbol, tick.bid, 0, 0, "UCP Sell"));

   if(ok)
   {
      avgDirty = true;
      PlaySound(EntrySound);
   }
}


//+------------------------------------------------------------------+
//| CloseAllPositionsOfSymbol                                        |
//+------------------------------------------------------------------+
void CloseAllPositionsOfSymbol(string symbol)
{
   int total = PositionsTotal();
   if(total <= 0)
   {
      avgDirty = true;
      return;
   }

   int count = 0;
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != symbol) continue;
      count++;
   }

   if(count == 0)
   {
      avgDirty = true;
      return;
   }

   ulong  tickets[];
   double volumes[];

   ArrayResize(tickets, count);
   ArrayResize(volumes, count);

   int idx = 0;
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != symbol) continue;

      tickets[idx] = ticket;
      volumes[idx] = PositionGetDouble(POSITION_VOLUME);
      idx++;
   }

   // --- ロット降順ソート ---
   for(int i = 0; i < count - 1; i++)
   {
      for(int j = i + 1; j < count; j++)
      {
         if(volumes[i] < volumes[j])
         {
            double v = volumes[i];
            volumes[i] = volumes[j];
            volumes[j] = v;

            ulong t = tickets[i];
            tickets[i] = tickets[j];
            tickets[j] = t;
         }
      }
   }

   // --- 非同期で一気にクローズを投げる ---
   trade.SetExpertMagicNumber((int)MagicNumber);
   trade.SetAsyncMode(true);

   bool anyClosed = false;

   for(int i = 0; i < count; i++)
   {
      ulong ticket = tickets[i];
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != symbol) continue;

      if(trade.PositionClose(ticket))
         anyClosed = true;
   }

   trade.SetAsyncMode(false);

   if(anyClosed)
      PlaySound(ExitSound);

   avgDirty = true;
}


//+------------------------------------------------------------------+
//| UI生成：Label                                                    |
//+------------------------------------------------------------------+
void CreateLabel(string name,int x,int y,string text)
{
   if(ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);

   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0,  name, OBJPROP_TEXT,      text);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  12);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     clrText);
}


//+------------------------------------------------------------------+
//| UI生成：Button                                                   |
//+------------------------------------------------------------------+
void CreateButton(string name,int x,int y,int w,int h,string text,
                  color bgColor,color textColor)
{
   if(ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);

   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,     w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,     h);
   ObjectSetString(0,  name, OBJPROP_TEXT,      text);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  12);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     textColor);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,   bgColor);
}


//+------------------------------------------------------------------+
//| UI生成：Edit                                                     |
//+------------------------------------------------------------------+
void CreateEdit(string name,int x,int y,int w,int h,
                color bgColor,color textColor)
{
   if(ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);

   ObjectCreate(0, name, OBJ_EDIT, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,     w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,     h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,   bgColor);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     textColor);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  12);
   ObjectSetInteger(0, name, OBJPROP_ALIGN,     0);
}


//+------------------------------------------------------------------+
//| UI生成：Panel Background                                         |
//+------------------------------------------------------------------+
void CreatePanelBackground(string name,int x,int y,int w,int h,
                           color bgColor,color borderColor)
{
   if(ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);

   ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,     w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,     h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,   bgColor);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     borderColor);
   ObjectSetInteger(0, name, OBJPROP_BACK,      false);
}
//+------------------------------------------------------------------+
