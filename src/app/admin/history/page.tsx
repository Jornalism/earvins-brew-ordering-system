'use client';
import {useState} from 'react';
import {useOrder} from '@/components/order-provider';
import {AdminOrderCard,philippineDate} from '@/components/admin/order-card';
export default function History(){const {orders}=useOrder();const [date,setDate]=useState('');const history=orders.filter(o=>(o.status==='Completed'||o.status==='Cancelled')&&(!date||(o.createdAt&&philippineDate(o.createdAt)===date)));return <><h1>Order History</h1><div className="admin-toolbar"><label>Date (Philippine time)<input type="date" value={date} onChange={e=>setDate(e.target.value)}/></label>{date&&<button className="admin-button secondary" onClick={()=>setDate('')}>Clear filter</button>}</div>{history.length?<div className="admin-grid">{history.slice().reverse().map(order=><AdminOrderCard key={order.id} order={order} history/>)}</div>:<p className="admin-empty">No completed or cancelled orders for this date.</p>}</>}
