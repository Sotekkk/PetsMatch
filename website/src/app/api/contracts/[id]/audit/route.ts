import { NextRequest, NextResponse } from 'next/server';
import { ContractService } from '@/lib/ContractService';

export async function GET(
  _req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;
  const service = new ContractService();
  const log = await service.getAuditLog(id);
  return NextResponse.json(log);
}
