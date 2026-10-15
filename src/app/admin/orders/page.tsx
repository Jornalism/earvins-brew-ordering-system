'use client';
import Link from 'next/link';
import {useOrder} from '@/components/order-provider';
import {AdminOrderCard} from '@/components/admin/order-card';
export default function Queue(){const {orders,loadExamples,demoLoaded}=useOrder();const active=orders.filter(o=>o.status!=='Completed'&&o.status!=='Cancelled');return <><div className="admin-title"><h1>Order Queue</h1>{!demoLoaded&&<button className="admin-button secondary" onClick={loadExamples}>Load demo orders</button>}</div><div className="admin-info">Queue numbers are for this local demo. Philippine-time daily resets will be connected with the backend.</div>{active.length?<div className="admin-grid">{active.map(order=><AdminOrderCard key={order.id} order={order}/>)}</div>:<p className="admin-empty">No active orders. Place a customer order or load demo orders.</p>}<Link className="text-link" href="/admin/history">View completed and cancelled orders</Link></>}
