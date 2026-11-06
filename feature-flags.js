/* Durable feature switch. To restore finance, change only finance to true and deploy.
   See FEATURE_STATE.md. Existing database records and finance code stay intact. */
(function(root){'use strict';
 const features=Object.freeze({finance:false,feeNotices:true});
 root.CheonglaFeatures=features;
 if(!features.finance&&root.document){root.document.documentElement.setAttribute('data-finance-paused','');const style=root.document.createElement('style');style.textContent='html[data-finance-paused] :is(#financeMenu,#billingPanel,#tuitionPaymentFilter,#examPaymentFilter,#tuitionPaymentSummary,#examPaymentSummary,label[for="tuitionPaymentFilter"],label[for="examPaymentFilter"]){display:none!important}';root.document.head.append(style);}
})(globalThis);
