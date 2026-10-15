import {OrderView} from '@/components/order-view';
export default async function Status({params}:{params:Promise<{id:string}>}){const {id}=await params;return <OrderView id={id} statusPage/>}
