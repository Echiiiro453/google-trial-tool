// frida-auto-trial.js — Avaliação Google One / AI: consultar e ativar via BillingClient
//
// Uso:
//   frida -H 127.0.0.1:<PORTA> -p <PID> -l frida-auto-trial.js
//
// Tag do logcat: AutoTrial
// O script shell auto-trial.sh altera as linhas de CONFIG abaixo.

// ===== CONFIG (auto-trial.sh altera estas variáveis) =====
var MODE = "activate";           // "list" | "activate" | "scan" | "discover" | "sniff"
var TARGET_PRODUCT = "auto";     // "auto" | "g1.play.ai.pro" | "g1.play.20tb"
var TARGET_OFFER = "";           // offerId específico (ex: "6months-eft-2")
var PREFER_DURATION = "longest"; // "longest" | "1mo" | "3mo" | "6mo" | "12mo"
var MODULE_APK = "/data/local/tmp/module.apk";
var EXTRA_PRODUCTS = "";         // IDs extras separados por vírgula
var INCLUDE_PROMOS = false;      // true para incluir ofertas com desconto (não $0.00)
var UPGRADE_MODE = false;        // true para usar SubscriptionUpdateParams (troca/stack de plano)
var OLD_PURCHASE_TOKEN = "";     // token lido do library.db ou passado via --old-token
var REPLACE_MODE = 5;            // 5 = CHARGE_FULL_PRICE (ideal para stack)
// ===== FIM CONFIG =====

Java.perform(function() {
    var TAG = "AutoTrial";
    var Log = Java.use("android.util.Log");
    var context = Java.use("android.app.ActivityThread").currentApplication().getApplicationContext();
    var Activity = Java.use("android.app.Activity");
    var ArrayList = Java.use("java.util.ArrayList");
    var List = Java.use("java.util.List");
    var Handler = Java.use("android.os.Handler");
    var Looper = Java.use("android.os.Looper");

    Log.i(TAG, "=== AUTO_TRIAL_START mode=" + MODE + " target=" + TARGET_PRODUCT + " prefer=" + PREFER_DURATION + " ===");

    // --- Modo Sniff: interceptar productIds que o próprio Google One consulta ---
    if (MODE === "sniff") {
        var seenSniff = {};
        try {
            var QpdBuilder = Java.use("com.android.billingclient.api.QueryProductDetailsParams$Product$Builder");
            QpdBuilder.setProductId.implementation = function(pid) {
                var s = String(pid);
                if (!seenSniff["q:" + s]) {
                    seenSniff["q:" + s] = true;
                    Log.i(TAG, "SNIFF_QUERY " + s);
                }
                return this.setProductId(pid);
            };
        } catch (e) {
            Log.w(TAG, "Sniff QueryProductDetailsParams indisponível: " + e);
        }
        try {
            var BfpBuilder = Java.use("com.android.billingclient.api.BillingFlowParams$ProductDetailsParams$Builder");
            BfpBuilder.setProductDetails.implementation = function(pd) {
                try {
                    Log.i(TAG, "SNIFF_FLOW " + String(pd.getProductId()));
                } catch (ex) {}
                return this.setProductDetails(pd);
            };
        } catch (e) {}
        Log.i(TAG, "=== SNIFF_READY ===");
        return;
    }

    // --- Carregar BillingClient a partir do APK de módulo ---
    var DexClassLoader = Java.use("dalvik.system.DexClassLoader");
    var dexLoader = DexClassLoader.$new(
        MODULE_APK,
        context.getCodeCacheDir().getAbsolutePath(),
        null,
        context.getClassLoader()
    );
    Java.classFactory.loader = dexLoader;

    var BillingClient = Java.use("com.android.billingclient.api.BillingClient");
    var QueryProductDetailsParams = Java.use("com.android.billingclient.api.QueryProductDetailsParams");
    var QpdProduct = Java.use("com.android.billingclient.api.QueryProductDetailsParams$Product");
    var BillingFlowParams = Java.use("com.android.billingclient.api.BillingFlowParams");
    var BfpProductDetailsParams = Java.use("com.android.billingclient.api.BillingFlowParams$ProductDetailsParams");
    var PurchasesUpdatedListener = Java.use("com.android.billingclient.api.PurchasesUpdatedListener");
    var BillingClientStateListener = Java.use("com.android.billingclient.api.BillingClientStateListener");
    var ProductDetailsResponseListener = Java.use("com.android.billingclient.api.ProductDetailsResponseListener");
    var ProductDetails = Java.use("com.android.billingclient.api.ProductDetails");
    var SubscriptionOfferDetails = Java.use("com.android.billingclient.api.ProductDetails$SubscriptionOfferDetails");
    var PricingPhase = Java.use("com.android.billingclient.api.ProductDetails$PricingPhase");

    var BASE_PRODUCTS = [
        "g1.play.ai.pro", "g1.play.20tb", "g1.play.2tb.ai",
        "g1.2tb.ai.subs_variant", "g1.ai.pro", "g1.30tb", "g1.2tb.ai"
    ];
    var SCAN_PRODUCTS = [
        "g1.100gb", "g1.200gb", "g1.2tb", "g1.5tb", "g1.10tb", "g1.20tb", "g1.30gb",
        "g1.play.100gb", "g1.play.200gb", "g1.play.2tb", "g1.play.5tb", "g1.play.10tb", "g1.play.30tb",
        "g1.100gb.yearly", "g1.200gb.yearly", "g1.2tb.yearly", "g1.2tb.ai.yearly", "g1.ai.pro.yearly",
        "g1.play.2tb.ai.yearly", "g1.play.ai.pro.yearly",
        "g1.play.2tb.ai.subs_variant", "g1.ai.pro.subs_variant", "g1.play.ai.pro.subs_variant",
        "g1.100gb.subs_variant", "g1.200gb.subs_variant", "g1.2tb.subs_variant",
        "g1.2tb.ai.annual", "g1.5tb.ai", "g1.play.5tb.ai", "g1.5tb.annual", "g1.2tb.annual", "g1.100gb.annual", "g1.200gb.annual", "g1.30gb.annual",
        "g1.20tb.v2", "g1.play.2tb.ai.student", "g1.student.2tb.ai", "g1.play.student.2tb.ai",
        "g1.play.2tb.ai_promo", "g1.2tb.ai_promo",
        // SKUs extras (18m/15m/12m/Ultra/Helium/30GB/Descontos)
        "g1.2tb.ai.18months_eft", "g1.2tb.ai.15months_eft", "g1.2tb.ai.12months_eft", "g1.2tb.ai.6months_eft", "g1.2tb.ai.3months_eft", "g1.2tb.ai.2months_eft",
        "g1.2tb.ai.12months_ip_75p", "g1.2tb.ai.12months_ip_90p", "g1.2tb.ai.2months_ip_50p", "g1.2tb.ai.3months_ip_50p",
        "g1.20tb.1month_eft.acq", "g1.ai.ultra.1month_eft.acq", "g1.20tb.3months_ip_90p.acq", "g1.ai.ultra.3months_ip_90p.acq",
        "g1.20tb.3months_ip_90p", "g1.20tb.3months_ip_80p", "g1.ai.ultra.3months_ip_75p.acq",
        "g1.2tb.1year_eft", "g1.2tb.6months_eft", "g1.2tb.3months_eft", "g1.2tb.1month_eft",
        "g1.2tb.12months_ip.4.99", "g1.2tb.6months_ip.4.99", "g1.2tb.3months_ip.2.49", "g1.2tb.1month_ip.2.49",
        "g1.2tb.1month_ip_50p", "g1.2tb.1month_ip_80p", "g1.2tb.1month_ip_85p.acq", "g1.2tb.1month_ip_90p.acq", "g1.2tb.1month_ip_95p.acq",
        "g1.2tb.2months_ip_50p.acq", "g1.2tb.2months_ip_75p", "g1.2tb.2months_ip_80p",
        "g1.2tb.3months_ip_50p", "g1.2tb.3months_ip_50p.acq", "g1.2tb.3months_ip_80p", "g1.2tb.3months_ip_85p.acq",
        "g1.2tb.annual.1month_eft", "g1.2tb.annual.3months_eft",
        "g1.2tb.annual.12months_ip_10p", "g1.2tb.annual.12months_ip_15p", "g1.2tb.annual.12months_ip_20p", "g1.2tb.annual.12months_ip_25p.acq", "g1.2tb.annual.12months_ip_40p",
        "g1.100gb.1year_eft", "g1.100gb.3months_eft", "g1.100gb.2months_eft", "g1.100gb.1month_eft",
        "g1.100gb.12months_ip.0.49", "g1.100gb.12months_ip.0.99", "g1.100gb.6months_ip.0.99", "g1.100gb.6months_ip_75p",
        "g1.100gb.3months_ip_50p", "g1.100gb.3months_ip_50p.acq", "g1.100gb.3months_ip_85p.acq",
        "g1.100gb.2months_ip_75p", "g1.100gb.1month_ip.0.49", "g1.100gb.1month_ip.0.99", "g1.100gb.1month_ip_50p", "g1.100gb.1month_ip_85p.acq", "g1.100gb.1month_ip_95p.acq",
        "g1.100gb.annual.1year_eft", "g1.100gb.annual.3months_eft", "g1.100gb.annual.1month_eft",
        "g1.100gb.annual.12months_ip_10p", "g1.100gb.annual.12months_ip_15p", "g1.100gb.annual.12months_ip_20p", "g1.100gb.annual.12months_ip_40p",
        "g1.200gb.1year_eft", "g1.200gb.3months_eft", "g1.200gb.1month_eft",
        "g1.200gb.12months_ip.1.49", "g1.200gb.6months_ip.1.49", "g1.200gb.3months_ip_50p", "g1.200gb.3months_ip_50p.acq", "g1.200gb.3months_ip_85p.acq",
        "g1.200gb.2months_ip_75p", "g1.200gb.1month_ip_50p", "g1.200gb.1month_ip_85p.acq", "g1.200gb.1month_ip_95p.acq",
        "g1.200gb.annual.3months_eft", "g1.200gb.annual.1month_eft",
        "g1.200gb.annual.12months_ip_10p", "g1.200gb.annual.12months_ip_15p", "g1.200gb.annual.12months_ip_20p", "g1.200gb.annual.12months_ip_40p",
        "g1.30gb.1month_eft", "g1.30gb.1month_ip_75p", "g1.30gb.1month_ip_85p.acq", "g1.30gb.1month_ip_95p.acq",
        "g1.30gb.3month_ip_75p", "g1.30gb.3months_ip_50p.acq", "g1.30gb.3months_ip_85p.acq", "g1.30gb.6month_ip_50p", "g1.30gb.12month_ip_50p",
        "g1.30gb.annual.1month_eft", "g1.30gb.annual.1year_ip_10p", "g1.30gb.annual.1year_ip_15p", "g1.30gb.annual.1year_ip_20p", "g1.30gb.annual.1year_ip_40p",
        "g1.play.helium", "g1.play.helium.student",
        "g1.helium.12months_ip_50p", "g1.helium.12months_ip_75p", "g1.helium.12months_ip_90p",
        "g1.helium.6months_ip_50p", "g1.helium.3months_ip_75p.acq", "g1.helium.2months_ip_50p", "g1.helium.1month_ip_75p.acq", "g1.helium.1month_ip_90p.acq", "g1.helium.1month_ip_95p",
        "g1.helium.annual.12months_ip_10p.acq", "g1.helium.annual.12months_ip_25p.acq",
        "g1.youtube_premium_individual_add_on"
    ];

    var PRODUCTS = [];
    var seenProd = {};
    function addProductId(id) {
        var clean = String(id || "").trim();
        if (clean && !seenProd[clean]) {
            seenProd[clean] = true;
            PRODUCTS.push(clean);
        }
    }
    for (var bp = 0; bp < BASE_PRODUCTS.length; bp++) addProductId(BASE_PRODUCTS[bp]);
    if (TARGET_PRODUCT && TARGET_PRODUCT !== "auto") {
        addProductId(TARGET_PRODUCT);
    }
    if (MODE === "scan" || MODE === "discover") {
        for (var sp = 0; sp < SCAN_PRODUCTS.length; sp++) addProductId(SCAN_PRODUCTS[sp]);
    }
    if (MODE === "discover") {
        var dPrefixes = ["g1.", "g1.play."];
        var dBases = [
            "100gb", "200gb", "500gb", "1tb", "2tb", "5tb", "10tb", "20tb", "30tb",
            "ai", "ai.plus", "ai.pro", "ai.ultra",
            "2tb.ai", "5tb.ai", "10tb.ai", "20tb.ai", "30tb.ai",
            "plus", "pro", "ultra", "student", "family"
        ];
        var dSuffixes = [
            "", ".subs_variant", ".annual", ".yearly", ".monthly",
            ".promo", ".trial", ".student", ".family", ".pixel",
            ".chromebook", "_promo", "_variant", ".v2", ".2",
            ".1m", ".3m", ".6m", ".12m", ".15m", ".18m", ".24m",
            ".1y", ".2y", ".3y",
            ".3mo", ".6mo", ".12mo", ".15mo", ".18mo", ".24mo",
            ".weekly", ".quarterly", ".semiannual",
            ".14d", ".30d", ".90d", ".365d",
            ".edu", ".partner", ".carrier", ".bundle", ".workspace",
            ".samsung", ".xiaomi", ".oneplus", ".tmobile", ".verizon"
        ];
        for (var dp = 0; dp < dPrefixes.length; dp++) {
            for (var db = 0; db < dBases.length; db++) {
                for (var ds = 0; ds < dSuffixes.length; ds++) {
                    addProductId(dPrefixes[dp] + dBases[db] + dSuffixes[ds]);
                }
            }
        }
        var altPrefixes = ["one.", "gemini.", "ai."];
        var altBases = ["pro", "plus", "ultra", "2tb", "5tb", "2tb.ai", "ai.pro", "student"];
        var altSuffixes = ["", ".monthly", ".annual", ".yearly", ".subs_variant", ".trial"];
        for (var ap = 0; ap < altPrefixes.length; ap++) {
            for (var ab = 0; ab < altBases.length; ab++) {
                for (var as = 0; as < altSuffixes.length; as++) {
                    addProductId(altPrefixes[ap] + altBases[ab] + altSuffixes[as]);
                }
            }
        }
        Log.i(TAG, "Discover matrix size: " + PRODUCTS.length + " IDs");
    }
    if (EXTRA_PRODUCTS) {
        var extraArr = String(EXTRA_PRODUCTS).split(",");
        for (var ep = 0; ep < extraArr.length; ep++) addProductId(extraArr[ep]);
    }

    var DUR = { "P1M": 1, "P3M": 3, "P6M": 6, "P1Y": 12 };
    var ALIAS = { "1mo": "P1M", "3mo": "P3M", "6mo": "P6M", "12mo": "P1Y" };

    function parseDurationDays(period) {
        var m = String(period || "").match(/^P(?:(\d+)Y)?(?:(\d+)M)?(?:(\d+)W)?(?:(\d+)D)?$/);
        if (!m) return 0;
        var y = parseInt(m[1] || "0", 10);
        var mo = parseInt(m[2] || "0", 10);
        var w = parseInt(m[3] || "0", 10);
        var d = parseInt(m[4] || "0", 10);
        return y * 365 + mo * 30 + w * 7 + d;
    }

    function parseDurationMonths(period) {
        if (DUR[period]) return DUR[period];
        var totalDays = parseDurationDays(period);
        return totalDays > 0 ? Math.round(totalDays / 30) : 0;
    }

    var GLOBAL_REFS = [];
    function keepAlive(obj) {
        GLOBAL_REFS.push(obj);
        return obj;
    }

    function withSystemLoader(fn) {
        var prev = Java.classFactory.loader;
        Java.classFactory.loader = null;
        try {
            return fn();
        } finally {
            Java.classFactory.loader = prev;
        }
    }

    function closeBillingClient() {
        try {
            if (bc && bc.isReady()) {
                bc.endConnection();
            }
        } catch (e) {}
    }

    // --- Retorno de chamada da compra ---
    var PLClass = keepAlive(Java.registerClass({
        name: "com.frida.auto.PL",
        implements: [PurchasesUpdatedListener],
        methods: {
            onPurchasesUpdated: function(br, purchases) {
                var code = br.getResponseCode();
                if (code === 0 && purchases != null) {
                    var pl = Java.cast(purchases, List);
                    for (var i = 0; i < pl.size(); i++) {
                        Log.i(TAG, "PURCHASE: " + String(pl.get(i).toString()).substring(0, 200));
                    }
                    Log.i(TAG, "=== TRIAL_ACTIVATED ===");
                } else if (code === 1) {
                    Log.i(TAG, "=== USER_CANCELLED ===");
                } else if (code === 7) {
                    Log.i(TAG, "=== ITEM_ALREADY_OWNED ===");
                } else {
                    Log.i(TAG, "=== PURCHASE_FAILED code=" + code + " msg=" + br.getDebugMessage() + " ===");
                }
                closeBillingClient();
            }
        }
    }));
    var purchaseListener = keepAlive(PLClass.$new());

    var builder = BillingClient.newBuilder(context).setListener(purchaseListener);
    try {
        var PendingPurchasesParams = Java.use("com.android.billingclient.api.PendingPurchasesParams");
        builder = builder.enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build());
    } catch (e) {
        builder = builder.enablePendingPurchases();
    }
    var bc = keepAlive(builder.build());

    var SLClass = keepAlive(Java.registerClass({
        name: "com.frida.auto.SL",
        implements: [BillingClientStateListener],
        methods: {
            onBillingSetupFinished: function(result) {
                if (result.getResponseCode() !== 0) {
                    Log.e(TAG, "=== CONNECT_FAILED code=" + result.getResponseCode() + " ===");
                    return;
                }
                Log.i(TAG, "BillingClient connected");

                var mainHandler = withSystemLoader(function() {
                    return Handler.$new(Looper.getMainLooper());
                });

                var Runnable = Java.use("java.lang.Runnable");
                var QRClass = keepAlive(Java.registerClass({
                    name: "com.frida.auto.QR",
                    implements: [Runnable],
                    methods: {
                        run: function() {
                            try {
                                doQuery();
                            } catch (e) {
                                Log.e(TAG, "=== LAUNCH_ERROR QR: " + e + " ===");
                                closeBillingClient();
                            }
                        }
                    }
                }));
                var queryRunnable = keepAlive(QRClass.$new());
                mainHandler.post(queryRunnable);
            },
            onBillingServiceDisconnected: function() {
                Log.w(TAG, "BillingClient desconectado");
            }
        }
    }));
    var stateListener = keepAlive(SLClass.$new());

    function checkExistingAndQuery() {
        try {
            var QueryPurchasesParams = Java.use("com.android.billingclient.api.QueryPurchasesParams");
            var PurchasesResponseListener = Java.use("com.android.billingclient.api.PurchasesResponseListener");
            var Purchase = Java.use("com.android.billingclient.api.Purchase");
            var qpp = QueryPurchasesParams.newBuilder().setProductType("subs").build();
            var PRLClass = keepAlive(Java.registerClass({
                name: "com.frida.auto.PRL",
                implements: [PurchasesResponseListener],
                methods: {
                    onQueryPurchasesResponse: function(br, purchasesList) {
                        try {
                            if (br.getResponseCode() === 0 && purchasesList != null) {
                                var pl = Java.cast(purchasesList, List);
                                if (pl.size() > 0) {
                                    Log.w(TAG, "ACTIVE_SUBS " + pl.size());
                                    for (var i = 0; i < pl.size(); i++) {
                                        var p = Java.cast(pl.get(i), Purchase);
                                        Log.w(TAG, "  ACTIVE_SUB: " + String(p.getProducts()));
                                    }
                                }
                            }
                        } catch (e) {}
                        try {
                            doQuery();
                        } catch (e2) {
                            Log.e(TAG, "=== LAUNCH_ERROR doQuery: " + e2 + " ===");
                            closeBillingClient();
                        }
                    }
                }
            }));
            bc.queryPurchasesAsync(qpp, keepAlive(PRLClass.$new()));
        } catch (e) {
            Log.w(TAG, "queryPurchasesAsync skip: " + e);
            doQuery();
        }
    }

    function doQuery() {
        var CHUNK_SIZE = 15;
        var chunks = [];
        for (var i = 0; i < PRODUCTS.length; i += CHUNK_SIZE) {
            chunks.push(PRODUCTS.slice(i, i + CHUNK_SIZE));
        }

        var aggregated = [];
        var chunkIdx = 0;

        var PDLClass = keepAlive(Java.registerClass({
            name: "com.frida.auto.PDL",
            implements: [ProductDetailsResponseListener],
            methods: { onProductDetailsResponse: function(br, pdList) {
                try {
                    var rawList = pdList;
                    try {
                        var QueryProductDetailsResult = Java.use("com.android.billingclient.api.QueryProductDetailsResult");
                        if (QueryProductDetailsResult.class.isInstance(pdList)) {
                            rawList = Java.cast(pdList, QueryProductDetailsResult).getProductDetailsList();
                        }
                    } catch (e) {}
                    if (rawList != null) {
                        var chunkList = Java.cast(rawList, List);
                        for (var x = 0; x < chunkList.size(); x++) {
                            aggregated.push(chunkList.get(x));
                        }
                    }
                    chunkIdx++;
                    if (chunkIdx < chunks.length) {
                        queryNextChunk();
                    } else {
                        onProducts(aggregated);
                    }
                } catch (e) {
                    Log.e(TAG, "=== LAUNCH_ERROR " + e + " ===");
                    closeBillingClient();
                }
            } }
        }));
        var pdl = keepAlive(PDLClass.$new());

        function queryNextChunk() {
            var batch = chunks[chunkIdx];
            var prodList = ArrayList.$new();
            for (var i = 0; i < batch.length; i++) {
                prodList.add(QpdProduct.newBuilder()
                    .setProductId(batch[i]).setProductType("subs").build());
            }
            var params = QueryProductDetailsParams.newBuilder().setProductList(prodList).build();
            bc.queryProductDetailsAsync(params, pdl);
        }

        if (chunks.length === 0) {
            onProducts([]);
        } else {
            queryNextChunk();
        }
    }

    function onProducts(list) {
        Log.i(TAG, "Products found: " + list.length);

        var REC_MODE = { 1: "INFINITE", 2: "FINITE", 3: "NON_RECURRING" };
        var trials = [];
        var promos = [];
        var allOffers = [];

        for (var i = 0; i < list.length; i++) {
            var pd = Java.cast(list[i], ProductDetails);
            var pid = String(pd.getProductId());
            var title = String(pd.getTitle());
            Log.i(TAG, "");
            Log.i(TAG, "PRODUCT " + pid + " — " + title);

            var offers = pd.getSubscriptionOfferDetails();
            if (offers == null) { Log.i(TAG, "  (sem ofertas)"); continue; }
            var ol = Java.cast(offers, List);

            for (var j = 0; j < ol.size(); j++) {
                var o = Java.cast(ol.get(j), SubscriptionOfferDetails);
                var oid = o.getOfferId();
                var basePlanId = "";
                try { basePlanId = String(o.getBasePlanId() || ""); } catch (e) {}
                var phases = Java.cast(o.getPricingPhases().getPricingPhaseList(), List);

                // Tags
                var tags = Java.cast(o.getOfferTags(), List);
                var tagArr = [];
                var tagStr = "";
                for (var t = 0; t < tags.size(); t++) {
                    var tg = String(tags.get(t));
                    tagArr.push(tg);
                    tagStr += (t > 0 ? "," : "") + tg;
                }

                var hasTrial = false;
                var hasPromo = false;
                var trialPeriod = "";
                var phase0Micros = -1;
                var phase0Price = "";
                var phase1Micros = -1;
                var phase1Price = "";
                var currency = "";
                var phase0Cycles = 1;
                var phaseListJson = [];

                for (var k = 0; k < phases.size(); k++) {
                    var ph = Java.cast(phases.get(k), PricingPhase);
                    var micros = Number(ph.getPriceAmountMicros());
                    var free = (micros === 0);
                    var period = String(ph.getBillingPeriod());
                    var fmtPrice = String(ph.getFormattedPrice());
                    var cycles = Number(ph.getBillingCycleCount());
                    var curCode = "";
                    try { curCode = String(ph.getPriceCurrencyCode() || ""); } catch (e) {}
                    var recModeNum = 0;
                    try { recModeNum = Number(ph.getRecurrenceMode()); } catch (e) {}
                    var recMode = REC_MODE[recModeNum] || String(recModeNum);

                    if (k === 0) {
                        phase0Micros = micros;
                        phase0Price = fmtPrice;
                        trialPeriod = period;
                        phase0Cycles = cycles > 0 ? cycles : 1;
                        currency = curCode;
                    }
                    if (k === 1) {
                        phase1Micros = micros;
                        phase1Price = fmtPrice;
                    }

                    var isDiscountedIntro = (k === 0 && !free && phases.size() > 1 && Number(Java.cast(phases.get(1), PricingPhase).getPriceAmountMicros()) > micros);

                    phaseListJson.push({
                        phase: k,
                        formattedPrice: fmtPrice,
                        priceMicros: micros,
                        currency: curCode,
                        period: period,
                        days: parseDurationDays(period),
                        cycles: cycles,
                        recurrenceMode: recMode
                    });

                    Log.i(TAG, "  [" + j + "] Fase" + k + ": " + fmtPrice
                        + " × " + period + " (" + cycles + " ciclos, " + recMode + ")"
                        + (free ? " ★GRÁTIS★" : (isDiscountedIntro ? " ★PROMO★" : ""))
                        + (k === 0 && basePlanId ? " base=" + basePlanId : "")
                        + (k === 0 && oid != null ? " id=" + oid : "")
                        + (tagStr && k === 0 ? " tags=[" + tagStr + "]" : ""));

                    if (k === 0 && free && phases.size() > 1) {
                        hasTrial = true;
                    } else if (isDiscountedIntro) {
                        hasPromo = true;
                    }
                }

                var days = parseDurationDays(trialPeriod) * phase0Cycles;
                var months = parseDurationMonths(trialPeriod) * phase0Cycles;
                var savings = 0;
                if (phases.size() > 1 && phase1Micros > phase0Micros && phase0Micros >= 0) {
                    savings = Math.round(((phase1Micros - phase0Micros) * phase0Cycles / 1000000) * 100) / 100;
                }

                var offerToken = "";
                try { offerToken = String(o.getOfferToken() || ""); } catch (e) {}

                var offerEntry = {
                    product: pid,
                    title: title,
                    basePlanId: basePlanId,
                    offerId: oid != null ? String(oid) : "",
                    offerToken: offerToken,
                    tags: tagArr,
                    isTrial: hasTrial,
                    isPromo: hasPromo,
                    duration: trialPeriod,
                    days: days,
                    months: months,
                    savings: savings,
                    currency: currency,
                    phases: phaseListJson,
                    pd: pd,
                    offer: o
                };
                allOffers.push(offerEntry);

                if (hasTrial) {
                    trials.push(offerEntry);
                } else if (hasPromo) {
                    promos.push(offerEntry);
                }
            }
        }

        trials.sort(function(a, b) { return b.days - a.days; });

        // Resumo
        Log.i(TAG, "");
        Log.i(TAG, "TRIALS_FOUND " + trials.length);
        for (var i = 0; i < trials.length; i++) {
            var t = trials[i];
            Log.i(TAG, "  TRIAL " + t.product + " / " + t.offerId + " — " + t.months + " meses grátis (" + t.days + "d, economia ~" + t.currency + " " + t.savings + ")");
        }

        if (promos.length > 0 && (INCLUDE_PROMOS || MODE === "scan" || MODE === "discover" || MODE === "list")) {
            Log.i(TAG, "PROMOS_FOUND " + promos.length);
            for (var p = 0; p < promos.length; p++) {
                var pr = promos[p];
                Log.i(TAG, "  PROMO " + pr.product + " / " + pr.offerId + " — " + pr.phases[0].formattedPrice + " (" + pr.duration + ") -> " + pr.phases[1].formattedPrice);
            }
        }

        if (MODE === "list" || MODE === "scan" || MODE === "discover") {
            for (var eIdx = 0; eIdx < allOffers.length; eIdx++) {
                var ex = allOffers[eIdx];
                Log.i(TAG, "JSON_EXPORT_ITEM " + JSON.stringify({
                    product: ex.product,
                    title: ex.title,
                    basePlanId: ex.basePlanId,
                    offerId: ex.offerId,
                    offerToken: ex.offerToken,
                    tags: ex.tags,
                    isTrial: ex.isTrial,
                    isPromo: ex.isPromo,
                    duration: ex.duration,
                    days: ex.days,
                    months: ex.months,
                    savings: ex.savings,
                    currency: ex.currency,
                    phases: ex.phases
                }));
            }
        }

        if (MODE === "list" || MODE === "scan" || MODE === "discover") {
            var doneTag = (trials.length === 0 && promos.length === 0) ? "NO_TRIALS" : "LIST_COMPLETE";
            Log.i(TAG, "=== " + doneTag + " ===");
            closeBillingClient();
            return;
        }

        var selected = null;
        if (TARGET_OFFER) {
            for (var i = 0; i < allOffers.length; i++) {
                if (allOffers[i].offerId === TARGET_OFFER && (TARGET_PRODUCT === "auto" || allOffers[i].product === TARGET_PRODUCT)) {
                    selected = allOffers[i];
                    break;
                }
            }
            if (!selected) {
                Log.e(TAG, "Oferta não encontrada para offerId=" + TARGET_OFFER + " alvo=" + TARGET_PRODUCT);
                Log.i(TAG, "=== SELECT_FAILED ===");
                closeBillingClient();
                return;
            }
        } else {
            if (trials.length === 0) {
                if (INCLUDE_PROMOS && promos.length > 0) {
                    trials = promos;
                } else {
                    Log.i(TAG, "=== NO_TRIALS ===");
                    closeBillingClient();
                    return;
                }
            }

            // Filtrar pelo produto alvo
            var candidates = [];
            for (var i = 0; i < trials.length; i++) {
                if (TARGET_PRODUCT === "auto" || trials[i].product === TARGET_PRODUCT) {
                    candidates.push(trials[i]);
                }
            }
            if (candidates.length === 0) {
                Log.e(TAG, "Nenhuma avaliação para alvo=" + TARGET_PRODUCT);
                Log.i(TAG, "=== SELECT_FAILED ===");
                closeBillingClient();
                return;
            }

            if (PREFER_DURATION === "longest") {
                selected = candidates[0];
                for (var i = 1; i < candidates.length; i++) {
                    if (candidates[i].days > selected.days) selected = candidates[i];
                }
            } else {
                var wantPeriod = ALIAS[PREFER_DURATION] || PREFER_DURATION;
                var wantMonths = parseDurationMonths(wantPeriod);
                for (var i = 0; i < candidates.length; i++) {
                    if (candidates[i].duration === wantPeriod || (wantMonths > 0 && candidates[i].months === wantMonths)) {
                        selected = candidates[i];
                        break;
                    }
                }
                if (!selected) {
                    Log.w(TAG, PREFER_DURATION + " não encontrado, usando a mais longa");
                    selected = candidates[0];
                    for (var i = 1; i < candidates.length; i++) {
                        if (candidates[i].days > selected.days) selected = candidates[i];
                    }
                }
            }
        }

        Log.i(TAG, "SELECTED " + selected.product + " / " + selected.offerId + " (" + selected.months + " meses)");
        Log.i(TAG, "Waiting for Activity to stabilize...");

        function getActiveActivity() {
            return withSystemLoader(function() {
                var AT = Java.use("android.app.ActivityThread");
                var athread = AT.currentActivityThread();
                var acts = athread.mActivities.value;
                var ait = acts.values().iterator();
                while (ait.hasNext()) {
                    var rec = ait.next();
                    var af = rec.getClass().getDeclaredField("activity");
                    af.setAccessible(true);
                    var a = Java.cast(af.get(rec), Activity);
                    if (!a.isFinishing() && !a.isDestroyed()) {
                        return a;
                    }
                }
                return null;
            });
        }

        // --- Obter Activity ---
        var act = null;
        try {
            act = getActiveActivity();
        } catch(e) {
            Log.e(TAG, "Erro na Activity: " + e);
            closeBillingClient();
            return;
        }
        if (!act) {
            Log.e(TAG, "=== NO_ACTIVITY ===");
            closeBillingClient();
            return;
        }

        // --- Iniciar fluxo de cobrança na thread de UI ---
        var token = selected.offer.getOfferToken();
        var finalPd = selected.pd;
        var finalAct = act;
        var finalToken = token;

        function launchWithOptionalUpgrade(oldToken) {
            var launchHandler = withSystemLoader(function() {
                return Handler.$new(Looper.getMainLooper());
            });

            var LRClass = keepAlive(Java.registerClass({
                name: "com.frida.auto.LR",
                implements: [Java.use("java.lang.Runnable")],
                methods: {
                    run: function() {
                        try {
                            var uiAct = finalAct;
                            try {
                                var freshAct = getActiveActivity();
                                if (freshAct) uiAct = freshAct;
                            } catch(ae) {}

                            var pdp = BfpProductDetailsParams.newBuilder()
                                .setProductDetails(finalPd).setOfferToken(finalToken).build();
                            var pdpList = ArrayList.$new();
                            pdpList.add(pdp);
                            var flowBuilder = BillingFlowParams.newBuilder()
                                .setProductDetailsParamsList(pdpList);

                            if (oldToken) {
                                var SubUpdateParams = Java.use("com.android.billingclient.api.BillingFlowParams$SubscriptionUpdateParams");
                                var sb = SubUpdateParams.newBuilder();
                                var modeApplied = false;
                                try {
                                    sb = sb.setReplaceProrationMode(REPLACE_MODE);
                                    modeApplied = true;
                                } catch (e1) {
                                    try {
                                        sb = sb.setReplaceSkusProrationMode(REPLACE_MODE);
                                        modeApplied = true;
                                    } catch (e2) {
                                        try {
                                            sb = sb.setSubscriptionReplacementMode(REPLACE_MODE);
                                            modeApplied = true;
                                        } catch (e3) {}
                                    }
                                }
                                var sup = sb.setOldPurchaseToken(String(oldToken)).build();
                                flowBuilder = flowBuilder.setSubscriptionUpdateParams(sup);
                                Log.i(TAG, "UPGRADE_PARAMS_ATTACHED mode=" + REPLACE_MODE + " applied=" + modeApplied);
                            }

                            var r = bc.launchBillingFlow(Java.cast(uiAct, Activity), flowBuilder.build());
                            Log.i(TAG, "BILLING_FLOW_LAUNCHED code=" + r.getResponseCode());
                        } catch(e) {
                            Log.e(TAG, "=== LAUNCH_ERROR " + e + " ===");
                            closeBillingClient();
                        }
                    }
                }
            }));
            var LaunchRunnable = keepAlive(LRClass.$new());
            launchHandler.postDelayed(LaunchRunnable, 1500);
        }

        if (OLD_PURCHASE_TOKEN) {
            launchWithOptionalUpgrade(OLD_PURCHASE_TOKEN);
        } else if (UPGRADE_MODE) {
            try {
                var upgradeHandled = false;
                var QueryPurchasesParams = Java.use("com.android.billingclient.api.QueryPurchasesParams");
                var PurchasesResponseListener = Java.use("com.android.billingclient.api.PurchasesResponseListener");
                var Purchase = Java.use("com.android.billingclient.api.Purchase");
                var qpp = QueryPurchasesParams.newBuilder().setProductType("subs").build();
                var UPLClass = keepAlive(Java.registerClass({
                    name: "com.frida.auto.UPL",
                    implements: [PurchasesResponseListener],
                    methods: {
                        onQueryPurchasesResponse: function(br, purchasesList) {
                            if (upgradeHandled) return;
                            upgradeHandled = true;
                            var oldTok = "";
                            try {
                                if (br.getResponseCode() === 0 && purchasesList != null) {
                                    var pl = Java.cast(purchasesList, List);
                                    if (pl.size() > 0) {
                                        var p0 = Java.cast(pl.get(0), Purchase);
                                        oldTok = String(p0.getPurchaseToken() || "");
                                        Log.i(TAG, "ACTIVE_SUB: " + String(p0.getProducts()));
                                    }
                                }
                            } catch (e) {
                                Log.w(TAG, "Erro lendo purchaseToken: " + e);
                            }
                            launchWithOptionalUpgrade(oldTok);
                        }
                    }
                }));
                bc.queryPurchasesAsync(qpp, keepAlive(UPLClass.$new()));
                setTimeout(function() {
                    if (!upgradeHandled) {
                        upgradeHandled = true;
                        Log.w(TAG, "queryPurchasesAsync sem resposta em 5s, seguindo sem oldPurchaseToken");
                        launchWithOptionalUpgrade("");
                    }
                }, 5000);
            } catch (e) {
                Log.w(TAG, "Upgrade queryPurchasesAsync falhou: " + e);
                launchWithOptionalUpgrade("");
            }
        } else {
            launchWithOptionalUpgrade("");
        }
    }

    bc.startConnection(stateListener);
});
setInterval(function(){}, 1000);
