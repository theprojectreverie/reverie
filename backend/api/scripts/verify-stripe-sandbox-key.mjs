import Stripe from 'stripe';
import {TEST_PACKAGES,SANDBOX_PRICES} from '../src/routes/shop.ts';
const key=process.env.REVERIE_STRIPE_SETUP_KEY??'';
if(!/^(sk|rk)_test_[A-Za-z0-9_]+$/.test(key)){
 console.error('No valid sandbox key supplied. Nothing changed.');process.exit(2);
}
try {
 const stripe=new Stripe(key,{timeout:10000,maxNetworkRetries:0});
 for(const pack of TEST_PACKAGES){
  const price=await stripe.prices.retrieve(SANDBOX_PRICES[pack.id]);
  if(price.livemode||!price.active||price.type!=='one_time'||price.currency!=='eur'||price.unit_amount!==pack.amountCents||price.product!=='reverie_sandbox_'+pack.id)throw Error('Catalogue mismatch');
 }
 console.log('Verified all three Project Reverie sandbox prices.');
}catch{
 console.error('Sandbox catalogue verification failed. Check the selected sandbox and key permissions. Nothing changed.');process.exitCode=1;
}
