'use client';
import Link from 'next/link';
import {usePathname} from 'next/navigation';
import {useCatalog} from '@/components/catalog-provider';
import {useOrder} from '@/components/order-provider';
const links=[['/admin/orders','Order Queue'],['/admin/history','Order History'],['/admin/products','Products'],['/admin/tables','Table QR']];
export function AdminShell({children}:{children:React.ReactNode}){const path=usePathname();const catalog=useCatalog();const orders=useOrder();return <div className="admin-shell"><nav className="admin-nav" aria-label="Admin navigation">{links.map(([href,label])=><Link key={href} href={href} aria-current={path===href?'page':undefined}>{label}</Link>)}</nav><div className="admin-content"><p className="admin-demo">Local demo · Changes are shared only in this browser and its same-origin tabs. Payments and pickup happen at the counter.</p>{(catalog.storageError||orders.storageError)&&<p role="alert" className="admin-error">{catalog.storageError||orders.storageError}</p>}{catalog.ready&&orders.ready?children:<p>Loading dashboard…</p>}</div></div>}
